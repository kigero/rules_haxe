import haxe.io.Path;
import sys.io.File;
import haxe.zip.Entry;
import haxe.crypto.Crc32;

using StringTools;

class Utils
{
	static function findFQCN(path:String):Array<String>
	{
		var content = File.getContent(path);
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

	private static function createFinalJar(intermediatePath:String, outputPath:String, srcs:Array<String>, strip = true, includeSources = true)
	{
		var toKeep = new Array<String>();

		for (src in srcs)
		{
			var fqcns = findFQCN(src);
			for (fqcn in fqcns)
			{
				fqcn = fqcn.replace(".", "/");

				toKeep.push(fqcn + ".class");
			}
		}

		var input = File.read(intermediatePath);
		var entries = haxe.zip.Reader.readZip(input);

		var out = File.write(outputPath, true);
		var outZip = new SingleEntryZipWriter(out);

		for (entry in entries)
		{
			if (strip && !toKeep.contains(entry.fileName))
			{
				continue;
			}
			outZip.writeEntry(entry);
		}

		if (includeSources)
		{
			var javaSrcDir = new Path(intermediatePath).dir + "/src";
			for (path in toKeep)
			{
				try
				{
					path = path.replace(".class", ".java");
					var bytes = File.getBytes(javaSrcDir + "/" + path);

					var entry:Entry =
						{
							fileName: path,
							fileSize: bytes.length,
							fileTime: Date.now(),
							compressed: false,
							dataSize: 0,
							data: bytes,
							crc32: Crc32.make(bytes)
						};
					outZip.writeEntry(entry);
				} catch (e:Any)
				{
					// Just ignore errors generating sources, these are likely from inner classes which aren't handled very well currently.
				}
			}
		}
		outZip.writeCDR();
		out.close();
	}

	private static function genMainTest(srcs:Array<String>)
	{
		var totalClasses = 0;
		var classes = new Map<String, Array<String>>();
		for (src in srcs)
		{
			var lst = findFQCN(src);
			classes.set(src, lst);
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

	static public function main()
	{
		var args = Sys.args();

		if (args.length == 0)
		{
			throw "No action provided.";
		}

		switch (args[0])
		{
			case "createFinalJar":
				createFinalJar(args[1], args[2], args.slice(5), args[3] == "true", args[4] == "true");

			case "genMainTest":
				genMainTest(args.slice(1));

			default:
				throw 'Bad action ${args[0]}';
		}
	}
}

/**
 * A ZIP file writer that allows individual entries to be written at one time; this prevents having to store all of the
 * entries in memory before they can be written.  There are two caveats to using this class over its super class:
 * 1. If the underlying *write* function is called with a list of entries, only the files that have been written already
 * will be included in the central directory record, and therefore only those file will be available in the output zip
 * file.
 * 1. Either *write* or *writeCDR* must be called before closing the zip file; otherwise the central directory record
 * will not be written.
 */
class SingleEntryZipWriter extends haxe.zip.Writer
{
	/**
	 * Constructor.
	 *
	 * @param o The output to write to.
	 */
	public function new(o:haxe.io.Output)
	{
		super(o);
	}

	/**
	 * Write a zip entry to this file.
	 *
	 * @param entry The entry to write.
	 */
	public function writeEntry(entry:haxe.zip.Entry)
	{
		// 'o' here is the reference to the output stream, which is stored in the super class.
		writeEntryHeader(entry);
		o.writeFullBytes(entry.data, 0, entry.data.length);
	}
}
