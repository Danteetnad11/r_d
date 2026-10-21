# 2026-10-20T20:25:38.239818900
import vitis

client = vitis.create_client()
client.set_workspace(path="Vitis")

comp = client.get_component(name="moving_max_pipeline")
comp.run(operation="PACKAGE")

comp = client.get_component(name="moving_max")
comp.run(operation="PACKAGE")

vitis.dispose()

vitis.dispose()

