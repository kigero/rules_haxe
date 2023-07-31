import sys.io.Process;
import haxe.display.Display.DisplayItem;
import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;
import haxe.zip.Entry;
import haxe.crypto.Crc32;

using StringTools;

class RulesHaxeUtils
{
	static function findFQCN(path:String):Array<String>
	{
		var content = File.getContent(path);
		var lines = content.split("\n");

		var pkg = null;
		var clsNames = new Array<String>();
		var privateClasses = new Array<String>();
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

						if (clsName.toLowerCase() == "abstract")
						{
							continue;
						}

						var isPrivate = false;
						if (idx > 0)
						{
							for (i in 0...idx)
							{
								if (tokens[i] == "private")
								{
									isPrivate = true;
									break;
								}
							}
						}

						if (isPrivate)
						{
							privateClasses.push(clsName);
						}
						else
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
			var mainClassName = null;

			for (idx in 0...clsNames.length)
			{
				if (idx == 0)
				{
					mainClassName = clsNames[0];
				}
				clsNames[idx] = '$pkg.${clsNames[idx]}';
			}
			for (idx in 0...privateClasses.length)
			{
				clsNames.push('$pkg._$mainClassName.${privateClasses[idx]}');
			}
		}

		return clsNames;
	}

	private static function findMatchingSourcePaths(path:String, matching:Array<String>, output:Array<String>, relPath = "")
	{
		for (child in FileSystem.readDirectory(path))
		{
			var fullPath = path + "/" + child;
			if (FileSystem.isDirectory(fullPath))
			{
				findMatchingSourcePaths(fullPath, matching, output, relPath + child + "/");
			}
			else
			{
				var fullRelPath = relPath + child;
				for (fqcn in matching)
				{
					if (fullRelPath.startsWith(fqcn) && fullRelPath.endsWith(".java"))
					{
						output.push(fullRelPath);
						break;
					}
				}
			}
		}
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
				toKeep.push(fqcn);
			}
		}

		var input = File.read(intermediatePath);
		var entries = haxe.zip.Reader.readZip(input);

		sys.FileSystem.createDirectory(haxe.io.Path.directory(outputPath));
		var out = File.write(outputPath, true);
		var outZip = new SingleEntryZipWriter(out);

		for (entry in entries)
		{
			if (strip)
			{
				if (entry.fileName.endsWith("/"))
				{
					continue;
				}

				if (entry.fileName.endsWith(".class"))
				{
					var inZip = false;
					for (fqcn in toKeep)
					{
						if (entry.fileName.startsWith(fqcn))
						{
							inZip = true;
							break;
						}
					}

					if (!inZip)
					{
						continue;
					}
				}
			}
			outZip.writeEntry(entry);
		}

		if (includeSources)
		{
			var javaSrcDir = new Path(intermediatePath).dir + "/src";
			var sourcePaths = new Array<String>();
			findMatchingSourcePaths(javaSrcDir, toKeep, sourcePaths);
			for (path in sourcePaths)
			{
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

	private static function findHXFiles(path:String, output:Array<String>, exclude:Array<String>, recursive = true, relPath = "")
	{
		for (child in FileSystem.readDirectory(path))
		{
			var fullPath = path + "/" + child;
			if (recursive && FileSystem.isDirectory(fullPath))
			{
				findHXFiles(fullPath, output, exclude, recursive, relPath + child + "/");
			}
			else if (child.endsWith(".hx"))
			{
				var fullRelPath = relPath + child;
				var isExcluded = false;
				for (ex in exclude)
				{
					if (fullRelPath.startsWith(ex))
					{
						isExcluded = true;
						break;
					}
				}
				if (!isExcluded)
				{
					output.push(fullRelPath);
				}
			}
		}
	}

	private static function genStdBuild(haxeInstallDir:String, target:String)
	{
		if (haxeInstallDir == ".")
		{
			// First see if there is an environment variable that sets haxe home.
			var haxeHome = Sys.getEnv("HAXE_HOME");
			if (haxeHome == null)
			{
				// If there is no environment variable, see if we can find it.
				try
				{
					var p = new Process("which", ["haxe"]);
					p.exitCode(true);
					var haxePath = p.stdout.readLine();
					haxeInstallDir = Path.directory(haxePath);
				} catch (e:Any)
				{
					//
				}
			}
			else
			{
				haxeInstallDir = haxeHome;
			}
		}
		var files = new Array<String>();
		findHXFiles(haxeInstallDir + "/std", files, [], false, "std/");
		findHXFiles(haxeInstallDir + "/std/haxe", files, ["std/haxe/macro/"], true, "std/haxe/");
		findHXFiles(haxeInstallDir + "/std/" + target, files, [], true, "std/" + target + "/");
		if (target != "js")
		{
			findHXFiles(haxeInstallDir + "/std/sys", files, [], true, "std/sys/");
		}

		var classes = new Array<String>();
		for (file in files)
		{
			for (cls in findFQCN(haxeInstallDir + "/" + file))
			{
				if (!classes.contains(cls) && !EXCLUDED_CLASSES.contains(cls) && !cls.startsWith(";") && !cls.contains("_"))
				{
					classes.push(cls);
				}
			}
		}

		for (cls in classes)
		{
			Sys.println("import " + cls + ";");
		}
		Sys.println("class StdBuild{ public static function main(){} }");
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

			case "genStdBuild":
				genStdBuild(args[1], args[2]);

			default:
				throw 'Bad action ${args[0]}';
		}
	}

	// @formatter:off
	private static var EXCLUDED_CLASSES = [
		"ArrayAccess",
		"haxe.IMap",
		"haxe.ds.TreeNode",
		"haxe.ds.GenericCell",
		"haxe.ds.GenericStackIterator",
		"haxe.ds.HashMapData",
		"haxe.ds.ListNode",
		"haxe.ds.ListIterator",
		"haxe.ds.ListKeyValueIterator",
		"haxe.Lock",
		"haxe.Mutex",
		"haxe.Thread",
		"haxe.EnumValueTools",
		"haxe.___Int64",
		"haxe.io.ArrayBufferViewImpl",
		"haxe.io.BytesDataImpl",
		"haxe.io.SingleHelper",
		"haxe.io.FloatHelper",
		"haxe.MainEvent",
		"haxe.rtti.TypeApi",
		"haxe.rtti.CTypeTools",
		"haxe.TimerTask",
		"haxe.DefaultResolver",
		"haxe.NullResolver",
		"haxe.xml.S",
		"haxe.xml.XmlParserException",
		"haxe.zip.HuffTools",
		"haxe.zip.Window",
		"java.db.JdbcConnection",
		"java.db.JdbcResultSet",
		"java.internal.IHxObject",
		"java.internal.DynamicObject",
		"java.internal.HxEnum",
		"java.internal.ParamEnum",
		"java.vm.AtomicNode",
		"java.vm.Node",
		"java.vm.HaxeThread",
		"ArrayIterator",
		"haxe.ds.IntMapKeyIterator",
		"haxe.ds.IntMapValueIterator",
		"haxe.ds.ObjectMapKeyIterator",
		"haxe.ds.ObjectMapValueIterator",
		"haxe.ds.StringMapKeyIterator",
		"haxe.ds.StringMapValueIterator",
		"haxe.ds.WeakMapKeyIterator",
		"haxe.ds.WeakMapValueIterator",
		"haxe.ds.Entry",
		"sys.io.ProcessInput",
		"js.TypeError",
		"js.RegExpMatch",
		"js.ReferenceError",
		"haxe.ds.StringMapIterator",
		"js.RangeError",
		"js.HaxeError",
		"js.SyntaxError",
		"js.html.ArrayBufferCompat",
		"HaxeRegExp",
		"js.EvalError",
		"js.URIError",
		"js.html.CanvasUtil",
		"sys.thread.HaxeThread",
		"haxe.zip.ExtraField",
		"haxe.display.DisplayMethods",
		"haxe.StackItem",
		"haxe.display.ServerMethods",
		"ValueType",
		"haxe.crypto.HashMethod",
		"haxe.display.Methods",
		"haxe.display.NoData",
		"haxe.rtti.Rights",
		"haxe.rtti.TypeTree",
		"haxe.TemplateExpr",
		"haxe.xml.Filter",
		"haxe.xml.Attrib",
		"haxe.xml.Rule",
		"haxe.xml.CheckResult",
		"haxe.zip.State",
        "haxe.NativeException",
        "sys.thread.NextEventTime"
	];
}
// @formatter:on 

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