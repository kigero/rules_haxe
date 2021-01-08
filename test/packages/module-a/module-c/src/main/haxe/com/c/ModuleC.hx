package com.c;

class ModuleC
{
	public function new()
	{
		//
	}

	public function get()
	{
		return "ModuleC";
	}

	public static function main()
	{
		var c = new ModuleC();
		trace(c.get());
	}
}
