set ModuleHierarchy {[{
"Name" : "moving_max", "RefName" : "moving_max","ID" : "0","Type" : "sequential",
"SubLoops" : [
	{"Name" : "INITIALIZE_WINDOW","RefName" : "INITIALIZE_WINDOW","ID" : "1","Type" : "no"},
	{"Name" : "PROCESS_SAMPLES","RefName" : "PROCESS_SAMPLES","ID" : "2","Type" : "no",
	"SubLoops" : [
	{"Name" : "SHIFT_WINDOW","RefName" : "SHIFT_WINDOW","ID" : "3","Type" : "no"},
	{"Name" : "FIND_MAXIMUM","RefName" : "FIND_MAXIMUM","ID" : "4","Type" : "no"},]},]
}]}