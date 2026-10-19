/*
 * Button-triggered frame capture application for MicroBlaze.
 */

//---------------------------INCLUDES----------------------------------//
#include <stdbool.h>

#include "xil_types.h"
#include "xstatus.h"

#include "xparameters.h"
#include "xgpio.h"
#include "xaxidma.h"

//---------------------------MACROS---------------------------------//
#define APP_FRAME_WIDTH              320U
#define APP_FRAME_HEIGHT             200U
#define APP_FRAME_BYTE_COUNT         (APP_FRAME_WIDTH * APP_FRAME_HEIGHT)
#define APP_FRAME_BUFFER_ADDRESS     ((UINTPTR)XPAR_AXI4_FULL_RAM_0_BASEADDR)

#define APP_BUTTON_CHANNEL           1U
#define APP_START_CHANNEL            2U
#define APP_GPIO_OUTPUT_DIRECTION    0U
#define APP_BUTTON_MASK              (1U << 0U)
#define APP_START_MASK               (1U << 0U)
#define APP_BUTTON_ACTIVE_LEVEL      1U

// Poll count, not milliseconds; no long delays in simulation.
#define APP_DMA_POLL_LIMIT           1000000U

#if APP_FRAME_BYTE_COUNT > (XPAR_AXI4_FULL_RAM_0_HIGHADDR - XPAR_AXI4_FULL_RAM_0_BASEADDR + 1U)
#error "The frame does not fit in axi4_full_ram."
#endif

//---------------------------TYPES-------------------------------------//
// Capture progress and errors visible in the debugger.
typedef enum
{
    APP_INITIALIZING = 0,
    APP_WAITING_FOR_BUTTON,
    APP_PREPARING_DMA,
    APP_RECEIVING_FRAME,
    APP_FRAME_COMPLETE,
    APP_GPIO_INITIALIZATION_ERROR,
    APP_DMA_INITIALIZATION_ERROR,
    APP_DMA_CONFIGURATION_ERROR,
    APP_DMA_TRANSFER_ERROR,
    APP_DMA_TIMEOUT,
    APP_FRAME_LENGTH_ERROR
} AppCaptureStatus;

//---------------------------LOCAL VARIABLES--------------------------//
// Peripheral instances persist for the lifetime of the application.
static XGpio control_gpio;
static XAxiDma frame_dma;

// Watch these variables in the debugger; this design has no UART.
volatile AppCaptureStatus capture_status = APP_INITIALIZING;
volatile u32 completed_frame_count = 0U;
volatile u32 received_byte_count = 0U;
volatile u32 last_dma_status = 0U;

//---------------------------LOCAL FUNCTION PROTOTYPES--------------------------//
static int app_init_gpio(void);
static int app_init_dma(void);
static int app_init(void);
static bool app_button_is_pressed(void);
static int app_wait_for_frame(void);
static int app_capture_frame(void);

//---------------------------LOCAL FUNCTIONS DEFINITIONS-------------------------//
/**
 * Initialize the button input and receiver start output on AXI GPIO.
 *
 * @return XST_SUCCESS on success, or the GPIO initialization error.
 */
static int app_init_gpio(void)
{
    int status;

    // Vitis SDT drivers identify peripherals by their base addresses.
    status = XGpio_Initialize(&control_gpio, XPAR_AXI_GPIO_0_BASEADDR);
    if (status != XST_SUCCESS)
    {
        capture_status = APP_GPIO_INITIALIZATION_ERROR;
        return status;
    }

    // Direction bits: 1 = input, 0 = output. Keep start low initially.
    XGpio_DiscreteWrite(&control_gpio, APP_START_CHANNEL, 0U);
    XGpio_SetDataDirection(&control_gpio, APP_START_CHANNEL, APP_GPIO_OUTPUT_DIRECTION);
    XGpio_SetDataDirection(&control_gpio, APP_BUTTON_CHANNEL, APP_BUTTON_MASK);
    return XST_SUCCESS;
}

/**
 * Initialize Simple DMA for stream-to-memory transfers with polling.
 *
 * @return XST_SUCCESS on success, or an initialization/configuration error.
 */
static int app_init_dma(void)
{
    XAxiDma_Config *dma_configuration;
    int status;

    dma_configuration = XAxiDma_LookupConfig(XPAR_AXI_DMA_0_BASEADDR);
    if (dma_configuration == NULL)
    {
        capture_status = APP_DMA_INITIALIZATION_ERROR;
        return XST_FAILURE;
    }

    status = XAxiDma_CfgInitialize(&frame_dma, dma_configuration);
    if (status != XST_SUCCESS)
    {
        capture_status = APP_DMA_INITIALIZATION_ERROR;
        return status;
    }

    // Require Simple DMA, an S2MM channel, and room for a complete frame.
    if (XAxiDma_HasSg(&frame_dma) || !frame_dma.HasS2Mm ||
        APP_FRAME_BYTE_COUNT > XAxiDma_GetRxRing(&frame_dma)->MaxTransferLen)
    {
        capture_status = APP_DMA_CONFIGURATION_ERROR;
        return XST_FAILURE;
    }

    XAxiDma_IntrDisable(&frame_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    return XST_SUCCESS;
}

/**
 * Initialize GPIO before DMA so the receiver start signal remains low.
 *
 * @return XST_SUCCESS on success, or the first peripheral initialization error.
 */
static int app_init(void)
{
    int status;

    status = app_init_gpio();
    if (status != XST_SUCCESS)
    {
        return status;
    }

    return app_init_dma();
}

/**
 * Read the button using the configured active level.
 *
 * @return true when pressed, false when released.
 */
static bool app_button_is_pressed(void)
{
    u32 button_value;

    button_value = XGpio_DiscreteRead(&control_gpio, APP_BUTTON_CHANNEL);
    return ((button_value & APP_BUTTON_MASK) != 0U) == APP_BUTTON_ACTIVE_LEVEL;
}

/**
 * Poll DMA completion and check the received frame length.
 *
 * @return XST_SUCCESS for a complete frame, or XST_FAILURE on error/timeout.
 */
static int app_wait_for_frame(void)
{
    u32 poll_count;

    for (poll_count = 0U; poll_count < APP_DMA_POLL_LIMIT; ++poll_count)
    {
        last_dma_status = XAxiDma_ReadReg(frame_dma.RegBase,
                                         XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);

        // Check errors before accepting the completion flag.
        if ((last_dma_status & (XAXIDMA_ERR_ALL_MASK | XAXIDMA_IRQ_ERROR_MASK)) != 0U)
        {
            capture_status = APP_DMA_TRANSFER_ERROR;
            return XST_FAILURE;
        }

        // IOC is set on completion even with interrupts disabled.
        if ((last_dma_status & XAXIDMA_IRQ_IOC_MASK) != 0U)
        {
            received_byte_count = XAxiDma_ReadReg(frame_dma.RegBase,
                                                XAXIDMA_RX_OFFSET + XAXIDMA_BUFFLEN_OFFSET);

            if (received_byte_count != APP_FRAME_BYTE_COUNT)
            {
                capture_status = APP_FRAME_LENGTH_ERROR;
                return XST_FAILURE;
            }

            XAxiDma_IntrAckIrq(&frame_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
            return XST_SUCCESS;
        }
    }

    capture_status = APP_DMA_TIMEOUT;
    return XST_FAILURE;
}

/**
 * Prepare DMA, start the receiver, and wait for one frame.
 *
 * @return XST_SUCCESS on completion, or a transfer error.
 */
static int app_capture_frame(void)
{
    int status;

    capture_status = APP_PREPARING_DMA;
    received_byte_count = 0U;
    XAxiDma_IntrAckIrq(&frame_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    // Arm DMA for 64000 bytes before allowing the receiver to capture.
    status = XAxiDma_SimpleTransfer(&frame_dma, APP_FRAME_BUFFER_ADDRESS,
                                   APP_FRAME_BYTE_COUNT, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS)
    {
        capture_status = APP_DMA_TRANSFER_ERROR;
        return status;
    }

    capture_status = APP_RECEIVING_FRAME;
    XGpio_DiscreteWrite(&control_gpio, APP_START_CHANNEL, APP_START_MASK);
    status = app_wait_for_frame();
    // A low start level allows a new rising edge for the next frame.
    XGpio_DiscreteWrite(&control_gpio, APP_START_CHANNEL, 0U);

    if (status != XST_SUCCESS)
    {
        // Stop here: start=0 does not abort an incomplete receiver frame.
        XAxiDma_Reset(&frame_dma);
        return status;
    }

    ++completed_frame_count;
    capture_status = APP_FRAME_COMPLETE;
    return XST_SUCCESS;
}

//---------------------------APPLICATION ENTRY POINT----------------------------//
/**
 * Initialize the application and capture one frame for each button press.
 *
 * @return Initialization or transfer error; otherwise the main loop runs forever.
 */
int main(void)
{
    int status;

    status = app_init();
    if (status != XST_SUCCESS)
    {
        return status;
    }

    while (TRUE)
    {
        capture_status = APP_WAITING_FOR_BUTTON;
        while (!app_button_is_pressed())
        {
            // Keep start low until the button is pressed.
        }

        status = app_capture_frame();
        if (status != XST_SUCCESS)
        {
            return status;
        }

        // Holding the button must not trigger another frame.
        while (app_button_is_pressed())
        {
        }
    }

    return XST_SUCCESS;
}
