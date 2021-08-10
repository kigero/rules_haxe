import sys
import os
import xml.etree.ElementTree as ET
import codecs
import shutil
import tempfile

TYPE_ENUM = 1
TYPE_INTERFACE = 2
TYPE_CLASS = 3
    
class MemberDesc:
    def parsePath(self, element):
        rtrn = element.attrib["path"] if "path" in element.attrib else ""
        if "Void" == rtrn:
            rtrn = "void"
        elif "Bool" == rtrn:
            rtrn = "boolean"
        elif "Any" == rtrn:
            return "Object"
        elif "a" in element.attrib and element.attrib["a"] == ":":
            return "Method"
        elif element.tag == "d":
            return "Object"
            
        if len(element) >= 1:
            subPath = self.parsePath(element[0])
            if subPath != None:
                rtrn += "<" + subPath + ">"
                
        return rtrn        
    
    def __init__(self, element):
        self.name = element.tag
        self.is_public = "public" in element.attrib and "1" == element.attrib["public"]
        self.is_override = "override" in element.attrib and "1" == element.attrib["override"]
        
        self.args = []
        self.arg_names = []
        self.comment = None
        self.is_method = False
        self.return_type = None
        
        for child in element:
            if child.tag == "c":
                self.is_method = False
                self.return_type = child.attrib["path"]
            elif child.tag == "f":
                self.is_method = True
                idx = 0
                a_val = child.attrib["a"]
                if a_val.find(":") >= 0:
                    for arg_name in a_val.split(":"):
                        if arg_name != None and arg_name != "":
                            self.arg_names.append(arg_name)
                            self.args.append(self.parsePath(child[idx]))
                        idx += 1
                elif a_val != "":
                    self.arg_names.append(a_val)
                    self.args.append(self.parsePath(child[idx]))
                    idx += 1
                self.return_type = self.parsePath(child[idx])
            elif child.tag == "haxe_doc":
                self.comment = child.text

class TypeDesc:
    def __init__(self, element):
        self.pkg = element.attrib["path"]
        
        last_dot = self.pkg.rfind(".")
        if last_dot > 0:
            self.name = self.pkg[last_dot + 1:]
            self.pkg = self.pkg[:last_dot]
        else:
            self.name = self.pkg
            self.pkg = ""
            
        self.fqpn = (self.pkg + "." if self.pkg != None and self.pkg != "" else "") + self.name
        
        self.is_private = "private" in element.attrib and "1" == element.attrib["private"]
        
        if element.tag == "enum":
            self.type = TYPE_ENUM
        elif "interface" in element.attrib and "1" == element.attrib["interface"]:
            self.type = TYPE_INTERFACE
        else:
            self.type = TYPE_CLASS
            
        self.implements = []
        self.extends = []
        self.members = []
        self.comment = None
        
        for child in element:
            if child.tag == "meta":
                continue
            elif child.tag == "haxe_doc":
                self.comment = child.text
                continue
            elif child.tag == "implements":
                self.implements.append(child.attrib["path"])
                continue
            elif child.tag == "extends":
                self.extends.append(child.attrib["path"])
                continue
            self.members.append(MemberDesc(child))     
            
def includePackage(in_pkg, packages, checkPkg):
    if in_pkg != None and not checkPkg.startswith(in_pkg):
        return False
    
    if packages != None:
        found = False
        for pkg in packages:
            if checkPkg.startswith(pkg):
                found = True
                break
        if not found:
            return False
            
    return True
    
def findMemberDesc(types, type, m_desc):
    for p_m_desc in type.members:
        if p_m_desc.name == m_desc.name and len(p_m_desc.arg_names) == len(m_desc.arg_names):
            if len(p_m_desc.arg_names) == 0:
                return p_m_desc
            
            matches = True
            for idx in range(len(p_m_desc.arg_names)):
                if p_m_desc.arg_names[idx] != m_desc.arg_names[idx] or p_m_desc.args[idx] != m_desc.args[idx]:
                    matches = False
                    break
            
            if matches:
                return p_m_desc
                
    return None 
    
def findParentComment(types, type, m_desc):
    parent_types = []
    for p_fqcn in type.extends:
        if p_fqcn in types:
            parent_types.append(types[p_fqcn])
    for p_fqcn in type.implements:
        if p_fqcn in types:
            parent_types.append(types[p_fqcn])
    for p_type in parent_types:
        p_m_desc = findMemberDesc(types, p_type, m_desc)
        if p_m_desc != None and p_m_desc.comment != None:
            return p_m_desc.comment
    for p_type in parent_types:
        comment = findParentComment(types, p_type, m_desc)
        if comment != None:
            return comment
    return None        

dox_path = sys.argv[1]
out_path = sys.argv[2]
in_pkg = None if sys.argv[3] == "*" else sys.argv[3]
packages = None
    
root = ET.parse(dox_path).getroot()

types = {}
for node in root:
    type = TypeDesc(node)
    types[type.fqpn] = type

for fqpn in types:
    if not includePackage(in_pkg, packages, fqpn):
        continue
        
    desc = types[fqpn]
    pkg_dir = os.path.join(out_path, desc.pkg.replace(".", "/"))
    if not os.path.exists(pkg_dir):
        os.makedirs(pkg_dir)
    cls_file = os.path.join(pkg_dir, desc.name + ".java")
    
    with codecs.open(cls_file, "w", "UTF-8") as out:
        if desc.pkg != "":
            out.write("package {};\n".format(desc.pkg))
            
        if desc.comment != None:
            out.write("/**\n\t{}\n */\n".format(desc.comment))
            
        out.write("private " if desc.is_private else "public ")
        if desc.type == TYPE_CLASS:
            out.write("class")
        elif desc.type == TYPE_INTERFACE:
            out.write("interface")
        elif desc.type == TYPE_ENUM:
            out.write("enum")
        out.write(" {}".format(desc.name))
        if len(desc.implements) > 0:
            out.write(" implements ")
            first = True
            for i_type in desc.implements:
                if not first:
                    out.write(", ")
                else:
                    first = False
                    
                out.write(i_type)
        if len(desc.extends) > 0:
            out.write(" extends ")
            first = True
            for e_type in desc.extends:
                if not first:
                    out.write(", ")
                else:
                    first = False
                    
                out.write(e_type)
        out.write("{\n")
        
        for idx, m_desc in enumerate(desc.members):
            if desc.type == TYPE_ENUM and idx > 0:
                out.write(",\n")
                
            comment = m_desc.comment
            if comment == None:
                comment = findParentComment(types, desc, m_desc)
            if comment != None:
                out.write("/**\n\t")
                out.write(comment)
                out.write("\n */\n")
            
            if desc.type == TYPE_ENUM:
                out.write(m_desc.name)
                continue
                
            if m_desc.is_override:
                out.write("@override ")
                
            out.write("public " if m_desc.is_public else "private ")
            
            if m_desc.is_method and m_desc.name == "new":
                out.write(desc.name[desc.name.rfind(".") + 1:])
            else:
                out.write("{} {}".format(m_desc.return_type, m_desc.name))
                
            if m_desc.is_method:
                out.write("(")
                first = True
                for idx, arg in enumerate(m_desc.args):
                    if not first:
                        out.write(", ")
                    else:
                        first = False
                    out.write("{} ".format(arg))
                    arg_name = m_desc.arg_names[idx]
                    if arg_name.startswith("?"):
                        arg_name = arg_name[1:]
                    out.write(arg_name)
                out.write(")")
                if desc.type == TYPE_CLASS:
                    out.write("{}")
            out.write(";\n")
            
        out.write("}\n")
