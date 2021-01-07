package com.a;

class ModuleA
{
	public function new()
	{
		//
	}

	public function get()
	{
		return "ModuleA";
	}

	public static function main()
	{
		var a = new ModuleA();
		trace(a.get());
	}
}
