package com.b;

import haxe.display.JsonModuleTypes;
import com.a.ModuleA;

class ModuleB
{
	private var a:ModuleA;

	public function new(a:ModuleA)
	{
		this.a = a;
	}

	public function get()
	{
		return a.get() + " ModuleB";
	}

	public static function main()
	{
		var b = new ModuleB(new ModuleA());
		trace(b.get());
	}
}
