# 2026-10-15T04:03:32.547193400
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../MicroBlaze/led_indication_wrapper.xsa",os = "standalone",cpu = "microblaze_0",domain_name = "standalone_microblaze_0",compiler = "gcc")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.create_app_component(name="app_component",platform = "$COMPONENT_LOCATION/../platform/export/platform/platform.xpfm",domain = "standalone_microblaze_0")

comp = client.get_component(name="app_component")
status = comp.import_files(from_loc="", files=["V:\Lesson10\Lesson10_1\Vitis\app_component\src\main.c"], is_skip_copy_sources = False)

status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../MicroBlaze/led_indication_wrapper.xsa")

status = platform.build()

status = platform.build()

comp.build()

component = client.get_component(name="app_component")

lscript = component.get_ld_script(path="V:\Lesson10\Lesson10_2\Vitis\app_component\src\lscript.ld")

lscript.update_memory_region("microblaze_0_local_memory_dlmb_bram_if_cntlr_memory_0", "0x50", "0x7fb0")

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

comp = client.get_component(name="app_component")
comp.set_app_config(key = "USER_COMPILE_DEFINITIONS", values = ["чччччччччччччччччччччччччччччч"])

comp.set_app_config(key = "USER_COMPILE_DEFINITIONS", values = ["чччччччччччччччччччччччччччччч"])

comp.set_app_config(key = "USER_COMPILE_DEFINITIONS", values = [""])

comp.set_app_config(key = "USER_COMPILE_DEFINITIONS", values = [""])

comp.set_app_config(key = "USER_COMPILE_DEFINITIONS", values = [""])

comp.set_app_config(key = "USER_COMPILE_DEFINITIONS", values = [""])

comp = client.get_component(name="app_component")
status = comp.clean()

comp = client.get_component(name="app_component")
comp.set_app_config(key = "USER_COMPILE_DEFINITIONS", values = ["APP_TIME_SCALE=1000"])

status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

comp = client.get_component(name="app_component")
comp.set_app_config(key = "USER_COMPILE_OPTIMIZATION_LEVEL", values = ["-O2"])

comp.set_app_config(key = "USER_COMPILE_OPTIMIZATION_LEVEL", values = ["-O2"])

comp.set_app_config(key = "USER_COMPILE_OPTIMIZATION_LEVEL", values = ["-O1"])

comp.set_app_config(key = "USER_COMPILE_OPTIMIZATION_LEVEL", values = ["-O2"])

comp.set_app_config(key = "USER_COMPILE_OPTIMIZATION_LEVEL", values = ["-O2"])

comp.set_app_config(key = "USER_UNDEFINED_SYMBOLS", values = ["APP_TIME_SCALE=1000"])

comp = client.get_component(name="app_component")
status = comp.clean()

status = platform.build()

comp.build()

comp = client.get_component(name="app_component")
comp.set_app_config(key = "USER_UNDEFINED_SYMBOLS", values = [""])

comp.set_app_config(key = "USER_UNDEFINED_SYMBOLS", values = [""])

comp = client.get_component(name="app_component")
status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

