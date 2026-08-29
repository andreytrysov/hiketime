#!/usr/bin/env python3
"""Приводит проект, сгенерированный XcodeGen, к формату Xcode 15.

XcodeGen 2.46 пишет формат 77 (Xcode 16). Простая замена номера версии
позволяет собирать из терминала, но редактор Xcode 15.4 падает на
конструкциях нового формата. Здесь честное понижение:
- objectVersion 60 (родной для Xcode 15, знает локальные Swift-пакеты);
- атрибуты формата 77 убираются;
- compatibilityVersion возвращается на место.
"""
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else "HikeTime.xcodeproj/project.pbxproj"
s = open(path).read()

s = re.sub(r"objectVersion = \d+;", "objectVersion = 60;", s)
s = re.sub(r"^\s*minimizedProjectReferenceProxies = \d+;\n", "", s, flags=re.M)
s = re.sub(r"^\s*preferredProjectObjectVersion = \d+;\n", "", s, flags=re.M)
if "compatibilityVersion" not in s:
    s = s.replace("\t\t\tbuildConfigurationList =",
                  '\t\t\tcompatibilityVersion = "Xcode 14.0";\n'
                  "\t\t\tbuildConfigurationList =", 1)
open(path, "w").write(s)
print("формат проекта приведён к Xcode 15")
