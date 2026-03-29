# Justfile to automate VMD RampenSau development

# Default recipe: launch VMD and load the plugin
run:
	vmd -e load_plugin.tcl

# Launch VMD with the test grid and the plugin
test:
	vmd -e vmd_test.tcl
