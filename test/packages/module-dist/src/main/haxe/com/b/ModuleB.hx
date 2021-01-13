package com.b;

import com.a.A;

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
