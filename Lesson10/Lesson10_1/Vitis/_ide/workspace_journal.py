# 2026-10-14T23:54:58.234181700
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis")

platform = client.get_component(name="platform")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../Zync_PS/led_indication_wrapper.xsa")

status = platform.build()

status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

status = platform.build()

comp.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../Zync_PS/led_indication_wrapper.xsa")

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../Zync_PS/led_indication_wrapper.xsa")

status = platform.build()

status = platform.build()

comp.build()

vitis.dispose()

