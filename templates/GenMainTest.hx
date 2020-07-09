import haxe.io.Path;

using StringTools;

class GenMainTest
{
	static function findFQCN(path:String):Array<String>
	{
		var content = sys.io.File.getContent(path);
		var lines = content.split("\n");

		var pkg = null;
		var clsNames = new Array<String>();
		var inComment = false;
		for (idx in 0...lines.length)
		{
			var line = lines[idx].trim();
			if (line.indexOf("/*") >= 0)
			{
				inComment = true;
			}

			if (!inComment)
			{
				if (line.startsWith("//"))
				{
					continue;
				}
				else if (line.indexOf("'") >= 0 || line.indexOf("\"") >= 0)
				{
					continue;
				}
				else if (line.startsWith("package"))
				{
					var semicolon = line.indexOf(';');
					try
					{
						pkg = line.substring(8, semicolon);
					} catch (e:Any)
					{
						//
					}
				}
				else
				{
					var tokens = line.split(" ");
					var idx = tokens.indexOf("class");
					if (idx < 0)
					{
						idx = tokens.indexOf("interface");
					}
					if (idx < 0)
					{
						idx = tokens.indexOf("enum");
					}

					if (idx >= 0)
					{
						var clsName = null;
						if (tokens.length == idx + 1)
						{
							idx++;
							line = lines[idx];
							tokens = line.split(" ");
							clsName = tokens[0];
						}
						else
						{
							clsName = tokens[idx + 1];
						}

						if (clsName.indexOf("<") >= 0)
						{
							clsName = clsName.substring(0, clsName.indexOf("<"));
						}

						if (clsName.toLowerCase() != "abstract")
						{
							clsNames.push(clsName);
						}
					}
				}
			}

			if (line.indexOf("*/") >= 0)
			{
				inComment = false;
			}
		}

		if (pkg != null)
		{
			for (idx in 0...clsNames.length)
			{
				clsNames[idx] = '$pkg.${clsNames[idx]}';
			}
		}

		return clsNames;
	}

	static public function main()
	{
		var args = Sys.args();

		if (args.length == 0)
		{
			throw "No input files provided.";
		}

		var totalClasses = 0;
		var classes = new Map<String, Array<String>>();
		for (arg in args)
		{
			var lst = findFQCN(arg);
			classes.set(arg, lst);
			totalClasses += lst.length;
		}

		if (totalClasses == 0)
		{
			throw "No classes found.";
		}

		for (path => lst in classes)
		{
			if (!path.endsWith("Test.hx"))
			{
				if (lst.length == 1)
				{
					Sys.println('import ${lst[0]};');
				}
				else
				{
					var pkg = lst[0];
					pkg = pkg.substring(0, pkg.lastIndexOf(".") + 1);
					pkg += new Path(path).file + ".*";

					Sys.println('import $pkg;');
				}
			}
		}
		Sys.println("\nclass MainTest\n{");
		Sys.println("\tstatic function main()\n\t{");
		Sys.println("\t\tvar r = new haxe.unit.TestRunner();");
		for (path => lst in classes)
		{
			if (path.endsWith("Test.hx"))
			{
				for (cls in lst)
				{
					if (cls.endsWith("Test"))
					{
						Sys.println('\t\tr.add(new $cls());');
					}
				}
			}
		}
		Sys.println("\t\tr.run();");
		Sys.println("\t\tif(r.result.toString().indexOf(\"FAILED\") >= 0)\n\t\t{");
		// Sys.println("\t\t\tSys.println(r.result.toString());");
		Sys.println("\t\t\tthrow \"Test failure.\";");
		Sys.println("\t\t}\n\t}\n}\n");
	}
}
