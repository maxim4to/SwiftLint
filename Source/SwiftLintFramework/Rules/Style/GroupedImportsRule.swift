import Foundation
import SourceKittenFramework

public struct GroupedImportsRule: CorrectableRule, ConfigurationProviderRule, OptInRule, AutomaticTestableRule {
    public var configuration = GroupedImportsConfiguration()

    public init() {}

    public static let description = RuleDescription(
        identifier: "grouped_imports",
        name: "Grouped Imports",
        description: "Imports should be separated into groups.",
        kind: .style,
        nonTriggeringExamples: [
            Example("import UIKit\nimport Foundation\n"),
            Example("import Alamofire\nimport GoogleMaps"),
            Example("import labc\nimport Ldef"),
            Example("import UIKit\n// comment\nimport Foundation\n\nimport GoogleMaps"),
            Example("@testable import AAA\nimport CCC"),
            Example("import UIKit\n@testable import Foundation"),
            Example("""
            import EEE.A
            import FFF.B
            #if os(Linux)
            import DDD.A
            import EEE.B
            #else
            import CCC
            import DDD.B
            #endif
            import AAA
            import BBB
            """)
        ],
        triggeringExamples: [
            Example("import UIKit\nimport GoogleMaps\n↓import Foundation"),
            Example("import UIKit\nimport GoogleMaps\n↓import Foundation\nimport Alamofire"),
            Example("@testable import GoogleMaps\n↓import UIKit")
            Example("import GoogleMaps\n↓@testable import UIKit"),
//            Example("""
//            import GoogleMaps
//            ↓import UIKit
//            #if DEBUG
//            import DebugPanels
//            ↓import AVFoundation
//            #else
//            import ReleasePanels
//            ↓import MetricKit
//            #endif
//            import AAA
//
//
//            ↓import BBB
//            """)
        ],
        corrections: [
            Example("import UIKit\nimport GoogleMaps\n↓import Foundation"):
                Example("import UIKit\nimport Foundation\n\nimport GoogleMaps")
        ]
    )

    public func validate(file: SwiftLintFile) -> [StyleViolation] {
        let sections = importSections(in: file, filterEnabled: false)
        return violatingOffsets(inSections: sections, file: file).map { index -> StyleViolation in
            let location = Location(file: file, characterOffset: index)
            return StyleViolation(ruleDescription: Self.description,
                                  severity: configuration.severityConfiguration.severity,
                                  location: location)
        }
    }

    public func correct(file: SwiftLintFile) -> [Correction] {
        let sections = importSections(in: file, filterEnabled: true)

        let corrections = violatingOffsets(inSections: sections, file: file).map { characterOffset -> Correction in
            let location = Location(file: file, characterOffset: characterOffset)
            return Correction(ruleDescription: Self.description, location: location)
        }

        guard corrections.isNotEmpty else {
            return []
        }

        let correctedContents = NSMutableString(string: file.contents)

        sections.reversed().forEach { lines in
            let groups = group(lines: lines)
            guard groups.count > 1 else {
                return
            }

            let shouldAddSpaceBetweenGroups = groups.contains { lines in
                lines.count >= configuration.minimumGroupSize
            }
            let separator = shouldAddSpaceBetweenGroups ? "\n\n" : "\n"
            let resultingLines: String = groups
                .map { lines in
                    lines.map { $0.content }.joined(separator: "\n")
                }
                .joined(separator: separator)

            guard let first = lines.first?.contentRange else {
                return
            }
            let groupRange = lines.dropFirst().reduce(first) { result, line in
                return NSUnionRange(result, line.contentRange)
            }

            correctedContents.replaceCharacters(in: groupRange, with: resultingLines)
        }

        file.write(correctedContents.bridge())

        return corrections
    }

    private func violatingOffsets(inSections sections: [[Line]], file: SwiftLintFile) -> [Int] {
        return sections.reduce(into: []) { partialResult, lines in
            let groups = group(lines: lines)
            guard groups.count > 1 else {
                return
            }

            var violatingOffsets: [Int] = []
            var currentImportLineIndex = lines.first!.index

            let shouldAddSpaceBetweenGroups = groups.contains { lines in
                lines.count >= configuration.minimumGroupSize
            }

            for group in groups {
                for line in group {
                    if line.index != currentImportLineIndex, currentImportLineIndex < file.lines.count {
//                        let currentImportLine = file.lines[currentImportLineIndex]
//                        let distance = line.content.distance(from: line.content.startIndex,
//                                                             to: currentImportLine.content.startIndex)
                        violatingOffsets.append(line.range.location)
                    }
                    currentImportLineIndex += 1
                }
                if shouldAddSpaceBetweenGroups {
                    currentImportLineIndex += 1
                }
            }

            partialResult.append(contentsOf: violatingOffsets)
        }
    }

    // Split imports to sections by interrupting lines like '#if DEBUG', '#endif' or any non-import lines
    private func importSections(in file: SwiftLintFile, filterEnabled: Bool) -> [[Line]] {
        var importRanges = file.match(pattern: "import\\s+\\w+", with: [.keyword, .identifier])
        if filterEnabled {
            importRanges = file.ruleEnabled(violatingRanges: importRanges, for: self)
        }

        guard importRanges.isNotEmpty else {
            return []
        }

        let contents = file.stringView
        let lines = file.lines
        let importLines: [Line] = importRanges.compactMap { range in
            guard let line = contents.lineAndCharacter(forCharacterOffset: range.location)?.line
                else { return nil }
            return lines[line - 1]
        }

        // interruptingLines - non empty lines between import lines
        var interruptingLines: [Line] = []
        if let firstImportLocation = importRanges.first?.location,
           let lastImportLocation = importRanges.last?.location,
           let firstImportLineIndex = contents.lineAndCharacter(forCharacterOffset: firstImportLocation)?.line,
           let lastImportLineIndex = contents.lineAndCharacter(forCharacterOffset: lastImportLocation)?.line,
           firstImportLineIndex != lastImportLineIndex {
            let importAndOtherStuffLines = lines[firstImportLineIndex - 1...lastImportLineIndex - 1]
            let importLinesIndexes = importLines.map { $0.index }
            interruptingLines = importAndOtherStuffLines.filter { line in
                !importLinesIndexes.contains(line.index) && line.content.isNotEmpty
            }
        }

        guard interruptingLines.isNotEmpty else {
            return [importLines]
        }

        var sections: [[Line]] = []
        var currentSection: [Line] = []
        var currentInterruptingLine: Line? = interruptingLines.first { line in
            line.index > importLines.first?.index ?? 0
        }
        importLines.forEach { line in
            if line.index < currentInterruptingLine?.index ?? 0 {
                currentSection.append(line)
            } else {
                sections.append(currentSection)
                currentInterruptingLine = interruptingLines.first { interruptingLine in
                    interruptingLine.index > line.index
                }
                currentSection = []
                currentSection.append(line)
            }
        }
        sections.append(currentSection)
        return sections
    }

    private func group(lines: [Line]) -> [[Line]] {
        guard lines.count > 1 else { return [lines] }

        let linesAndModules = lines.map { (line: $0, moduleName: String($0.importModule())) }
        let declaredModules = linesAndModules.map { $0.moduleName }

        let moduleGroups = configuration.moduleGroups.filter { group in
            group.modules.intersection(declaredModules).isNotEmpty
        }

        var result: [[Line]] = []

        // Retrieve lines for each group and add them to result
        for importGroup in moduleGroups {
            let modules = importGroup.modules.intersection(declaredModules)
            let lines = linesAndModules
                .filter { _, moduleName in
                    modules.contains(moduleName)
                }
                .map { line, _ in
                    line
                }
            result.append(lines)
        }

        // Add the rest of the modules into separate group
        let alreadyGroupedModules = result
            .reduce(into: []) { $0.append(contentsOf: $1) }
            .map { String($0.importModule()) }
        let unknownImportLines: [Line] = linesAndModules.compactMap { line, moduleName in
            if !alreadyGroupedModules.contains(moduleName) {
                return line
            } else {
                return nil
            }
        }
        if unknownImportLines.isNotEmpty {
            result.append(unknownImportLines)
        }

        return result
    }
}

fileprivate extension Line {
    var contentRange: NSRange {
        return NSRange(location: range.location, length: content.bridge().length)
    }

    // `Line` in this rule always contains word import
    // This method returns contents of line that are after import
    func importModule() -> Substring {
        return content[importModuleRange()]
    }

    func importModuleRange() -> Range<String.Index> {
        let rangeOfImport = content.range(of: "import")
        precondition(rangeOfImport != nil)
        let moduleStart = content.rangeOfCharacter(from: CharacterSet.whitespaces.inverted, options: [],
                                                   range: rangeOfImport!.upperBound..<content.endIndex)
        return moduleStart!.lowerBound..<content.endIndex
    }
}
