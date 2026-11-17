# Regenerates Tests/ABSmartlyTests/ReadmeSnippets.swift from README.md:
#   python3 scripts/readme-snippets.py README.md Tests/ABSmartlyTests/ReadmeSnippets.swift
# Blocks declaring types stay at file scope; other blocks become the body of an async function.
import re, sys
readme = open(sys.argv[1]).read()
blocks = re.findall(r"```swift\n(.*?)```", readme, re.S)

def guard(b):
    # The platform frameworks a block needs.
    if "import SwiftUI" in b: return "canImport(SwiftUI) && canImport(UIKit)"
    if "import Cocoa" in b: return "canImport(AppKit)"
    if "UIKit" in b or "UIDevice" in b: return "canImport(UIKit)"
    return None

def declares_types(b):
    return re.search(r"^(@\w+.*\n)*(public |final )*(class|struct|actor) ", b, re.M) is not None
out = ["""// Every ```swift block in README.md, compiled as part of the test target. Generated from the
// README by scripts/readme-snippets.py; ReadmeSnippetsTest fails when a README block is missing here, so keep them in sync.
// Blocks that need UIKit, SwiftUI or AppKit only compile where those frameworks exist.
import ABSmartly
import ABSmartlyAsync
import Foundation
import PromiseKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(AppKit)
import Cocoa
#endif
"""]
def body(b):
    return "\n".join(l for l in b.rstrip("\n").splitlines() if not l.startswith("import "))
def indent(t, n=1):
    return "\n".join(("\t" * n + l) if l.strip() else "" for l in t.splitlines())
for i, b in enumerate(blocks):
    if i == 0:
        continue
    out.append(f"// README block {i}")
    if declares_types(b):
        g = guard(b)
        if g: out.append(f"#if {g}")
        out.append(body(b))
        if g: out.append("#endif")
    else:
        g = guard(b)
        if g: out.append(f"#if {g}")
        out.append("@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)")
        out.append(f"func readmeSnippet{i}(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {{")
        out.append(indent(body(b)))
        # README examples bind values they do not use; reference them so the build stays warning-free.
        names = re.findall(r"^let (\w+)", body(b), re.M)
        if names:
            out.extend(indent(f"_ = {n}") for n in names)
        out.append("}")
        if g: out.append("#endif")
    out.append("")
open(sys.argv[2], "w").write("\n".join(out))
