# 2026-10-20T16:41:00.506844800
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis")

comp = client.create_hls_component(name = "moving_max",part = "xc7z020clg400-1",cfg_file = ["hls_config.cfg"],template = "empty_hls_component")

cfg = client.get_config_file(path="V:\Lesson15\Vitis\moving_max\hls_config.cfg")

cfg.set_values(key="syn.file", values=["moving_max.h"])

cfg.set_values(key="syn.file", values=["moving_max.h", "moving_max.c"])

cfg.set_values(key="tb.file", values=["tb_moving_max.c"])

comp = client.get_component(name="moving_max")
comp.run(operation="C_SIMULATION")

comp.run(operation="SYNTHESIS")

comp.run(operation="C_SIMULATION")

comp.run(operation="SYNTHESIS")

comp = client.create_hls_component(name = "moving_max_pipeline",part = "xc7z020clg400-1",cfg_file = ["hls_config.cfg"],template = "empty_hls_component")

cfg = client.get_config_file(path="V:\Lesson15\Vitis\moving_max_pipeline\hls_config.cfg")

cfg.set_values(key="syn.file", values=["moving_max.h"])

cfg.set_values(key="syn.file", values=["moving_max.h", "moving_max.c"])

cfg.set_values(key="tb.file", values=["tb_moving_max.c"])

comp = client.get_component(name="moving_max_pipeline")
comp.run(operation="C_SIMULATION")

comp.run(operation="SYNTHESIS")

comp.run(operation="SYNTHESIS")

comp.run(operation="SYNTHESIS")

comp.run(operation="C_SIMULATION")

comp.run(operation="CO_SIMULATION")

comp = client.get_component(name="moving_max")
comp.run(operation="CO_SIMULATION")

comp.run(operation="SYNTHESIS")

comp.run(operation="C_SIMULATION")

comp.run(operation="CO_SIMULATION")

vitis.dispose()

