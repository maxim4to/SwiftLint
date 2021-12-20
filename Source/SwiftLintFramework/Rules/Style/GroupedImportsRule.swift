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
            Example("import AAA\nimport ZZZ\nimport ↓BBB\nimport CCC"),
            Example("import DDD\n// comment\nimport CCC\nimport ↓AAA"),
            Example("@testable import CCC\nimport   ↓AAA"),
            Example("import CCC\n@testable import   ↓AAA"),
            Example("""
            import FFF.B
            import ↓EEE.A
            #if os(Linux)
            import DDD.A
            import EEE.B
            #else
            import DDD.B
            import ↓CCC
            #endif
            import AAA
            import BBB
            """)
        ],
        corrections: [
            Example("import AAA\nimport ZZZ\nimport ↓BBB\nimport CCC"):
                Example("import AAA\nimport BBB\nimport CCC\nimport ZZZ"),
            Example("import BBB // comment\nimport ↓AAA"): Example("import AAA\nimport BBB // comment"),
            Example("import BBB\n// comment\nimport CCC\nimport ↓AAA"):
                Example("import BBB\n// comment\nimport AAA\nimport CCC"),
            Example("@testable import CCC\nimport  ↓AAA"): Example("import  AAA\n@testable import CCC"),
            Example("import CCC\n@testable import  ↓AAA"): Example("@testable import  AAA\nimport CCC"),
            Example("""
            import FFF.B
            import ↓EEE.A
            #if os(Linux)
            import DDD.A
            import EEE.B
            #else
            import DDD.B
            import ↓CCC
            #endif
            import AAA
            import BBB
            """):
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
        ]
    )

    public func validate(file: SwiftLintFile) -> [StyleViolation] {
        let groups = importGroups(in: file, filterEnabled: false)
        return violatingOffsets(inGroups: groups, file: file).map { index -> StyleViolation in
            let location = Location(file: file, characterOffset: index)
            return StyleViolation(ruleDescription: Self.description,
                                  severity: configuration.severityConfiguration.severity,
                                  location: location)
        }
    }
    
    public func correct(file: SwiftLintFile) -> [Correction] {
        let groups = importGroups(in: file, filterEnabled: true)

        let corrections = violatingOffsets(inGroups: groups, file: file).map { characterOffset -> Correction in
            let location = Location(file: file, characterOffset: characterOffset)
            return Correction(ruleDescription: Self.description, location: location)
        }

        guard corrections.isNotEmpty else {
            return []
        }

        let correctedContents = NSMutableString(string: file.contents)

        groups.reversed().forEach { lines in
            let resultingLineGroups = group(lines: lines)
            guard resultingLineGroups.count > 1 else {
                return
            }
                        
            let shouldAddSpaceBetweenGroups = resultingLineGroups.contains { lines in
                lines.count >= configuration.minimumGroupSize
            }
            let separator = shouldAddSpaceBetweenGroups ? "\n\n" : "\n"
            let resultingLines: String = resultingLineGroups
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
    
    private func violatingOffsets(inGroups groups: [[Line]], file: SwiftLintFile) -> [Int] {
        return groups.reduce(into: []) { partialResult, lines in
            let resultingLineGroups = group(lines: lines)
            guard resultingLineGroups.count > 1 else {
                return
            }
            
            var violatingOffsets: [Int] = []
            var currentImportLineIndex = lines.first!.index
            
            let shouldAddSpaceBetweenGroups = resultingLineGroups.contains { lines in
                lines.count >= configuration.minimumGroupSize
            }
            
            for group in resultingLineGroups {
                for line in group {
                    if line.index != currentImportLineIndex, currentImportLineIndex < file.lines.count {
                        let currentImportLine = file.lines[currentImportLineIndex]
                        let distance = line.content.distance(from: line.content.startIndex, to: currentImportLine.content.startIndex)
                        violatingOffsets.append(line.range.location + distance)
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
    
    // Group imports by interrupting lines like '#if DEBUG', '#endif' or any non-import lines
    private func importGroups(in file: SwiftLintFile, filterEnabled: Bool) -> [[Line]] {
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
        
        // Non empty lines between import lines
        var interruptingLines: [Line] = []
        if let firstImportLocation = importRanges.first?.location,
           let lastImportLocation = importRanges.last?.location,
           let firstImportLineIndex = contents.lineAndCharacter(forCharacterOffset: firstImportLocation)?.line,
           let lastImportLineIndex = contents.lineAndCharacter(forCharacterOffset: lastImportLocation)?.line,
           firstImportLineIndex != lastImportLineIndex
        {
            let importAndOtherStuffLines = lines[firstImportLineIndex...lastImportLineIndex]
            let importLinesIndexes = importLines.map { $0.index }
            interruptingLines = importAndOtherStuffLines.filter { line in
                !importLinesIndexes.contains(line.index) && line.content.isNotEmpty
            }
        }
        
        guard interruptingLines.isNotEmpty else {
            return [importLines]
        }
        
        var groups: [[Line]] = []
        var currentGroup: [Line] = []
        var currentInterruptingLine: Line? = interruptingLines.first { line in
            line.index > importLines.first?.index ?? 0
        }
        importLines.forEach { line in
            if line.index < currentInterruptingLine?.index ?? 0 {
                currentGroup.append(line)
            } else {
                groups.append(currentGroup)
                currentInterruptingLine = interruptingLines.first { interceptingLine in
                    interceptingLine.index > line.index
                }
                currentGroup = []
                currentGroup.append(line)
            }
        }
        groups.append(currentGroup)
        return groups
    }
    
    private func group(lines: [Line]) -> [[Line]] {
        guard lines.count > 1 else { return [lines] }
        
        // Объявленные импорты в файле
        let declaredModulesData = lines.map { (line: $0, moduleName: String($0.importModule())) }
        let declaredModules = declaredModulesData.map { $0.moduleName }
        
        // Требуемые группы импортов
        let resultingImportGroups = configuration.moduleGroups.filter { group in
            group.modules.intersection(declaredModules).isNotEmpty
        }
        
        // Итоговый порядок строк
        var resultingLineGroups: [[Line]] = []
        
        // Для каждой группы находим строки
        for importGroup in resultingImportGroups {
            let modules = importGroup.modules.intersection(declaredModules)
            let lines = declaredModulesData
                .filter { (_, moduleName) in
                    modules.contains(moduleName)
                }
                .map { (line, _) in
                    line
                }
            resultingLineGroups.append(lines)
        }
        
        // Добавим остальные модули в новую группу
        let alreadyGroupedModules = resultingLineGroups
            .reduce([], +)
            .map { String($0.importModule()) }
        let unknownImportLines: [Line] = declaredModulesData.compactMap { line, moduleName in
            if !alreadyGroupedModules.contains(moduleName) {
                return line
            } else {
                return nil
            }
        }
        if unknownImportLines.isNotEmpty {
            resultingLineGroups.append(unknownImportLines)
        }
        
        return resultingLineGroups
    }
}

extension Line {
    fileprivate var contentRange: NSRange {
        return NSRange(location: range.location, length: content.bridge().length)
    }

    // `Line` in this rule always contains word import
    // This method returns contents of line that are after import
    fileprivate func importModule() -> Substring {
        return content[importModuleRange()]
    }

    fileprivate func importModuleRange() -> Range<String.Index> {
        let rangeOfImport = content.range(of: "import")
        precondition(rangeOfImport != nil)
        let moduleStart = content.rangeOfCharacter(from: CharacterSet.whitespaces.inverted, options: [],
                                                   range: rangeOfImport!.upperBound..<content.endIndex)
        return moduleStart!.lowerBound..<content.endIndex
    }
}
