# Zybo Z7-20: four LEDs for the running-light pattern.
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {LED_GPIO_tri_o[0]}]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {LED_GPIO_tri_o[1]}]
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports {LED_GPIO_tri_o[2]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {LED_GPIO_tri_o[3]}]

# BTN0..BTN3: software assigns speed-up, slow-down, pause, and resume.
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports {Button_GPIO_tri_i[0]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports {Button_GPIO_tri_i[1]}]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33} [get_ports {Button_GPIO_tri_i[2]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports {Button_GPIO_tri_i[3]}]

# Configure axi_gpio_2: GPIO Width = 1, All Inputs enabled.
# SW0 selects direction through Switch_GPIO_tri_i[0].
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports {Switch_GPIO_tri_i[0]}]

set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports sysclk]
create_clock -name sys_clk_pin -period 8.000 [get_ports sysclk]

set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports reset_rtl_0]