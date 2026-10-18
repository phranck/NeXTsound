import Foundation
import SwiftParser
import SwiftSyntax

enum LayoutError: Error {
    case invalidUTF8
    case invalidSyntax
    case changedTokens
    case changedComments
}

private protocol CommaSeparatedElement: SyntaxProtocol {
    var trailingComma: TokenSyntax? { get set }
}

extension FunctionParameterSyntax: CommaSeparatedElement {}
extension LabeledExprSyntax: CommaSeparatedElement {}

final class LayoutRewriter: SyntaxRewriter {
    override func visit(_ node: GuardStmtSyntax) -> StmtSyntax {
        let visited = super.visit(node)
        guard
            var rewritten = visited.as(GuardStmtSyntax.self),
            rewritten.conditions.count > 1
        else {
            return visited
        }
        var conditions = Array(rewritten.conditions)
        let firstBoundary = rewritten.guardKeyword.trailingTrivia + conditions[0].leadingTrivia
        rewritten.guardKeyword.trailingTrivia = []
        conditions[0].leadingTrivia = normalizedBoundary(firstBoundary)
        for index in 1 ..< conditions.count {
            guard var comma = conditions[index - 1].trailingComma else {
                return visited
            }
            let boundary = comma.trailingTrivia + conditions[index].leadingTrivia
            comma.trailingTrivia = []
            conditions[index - 1].trailingComma = comma
            conditions[index].leadingTrivia = normalizedBoundary(boundary)
        }
        let lastIndex = conditions.count - 1
        let lastBoundary = conditions[lastIndex].trailingTrivia + rewritten.elseKeyword.leadingTrivia
        conditions[lastIndex].trailingTrivia = []
        rewritten.elseKeyword.leadingTrivia = normalizedBoundary(lastBoundary)
        rewritten.conditions = ConditionElementListSyntax(conditions)
        return StmtSyntax(rewritten)
    }

    override func visit(_ node: FunctionParameterClauseSyntax) -> FunctionParameterClauseSyntax {
        var rewritten = super.visit(node)
        var opening = rewritten.leftParen
        var closing = rewritten.rightParen
        let parameters = compactList(Array(rewritten.parameters), opening: &opening, closing: &closing)
        rewritten.leftParen = opening
        rewritten.rightParen = closing
        rewritten.parameters = FunctionParameterListSyntax(parameters)
        return rewritten
    }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let visited = super.visit(node)
        guard
            var rewritten = visited.as(FunctionCallExprSyntax.self),
            var opening = rewritten.leftParen,
            var closing = rewritten.rightParen
        else {
            return visited
        }
        let arguments = compactList(Array(rewritten.arguments), opening: &opening, closing: &closing)
        rewritten.leftParen = opening
        rewritten.rightParen = closing
        rewritten.arguments = LabeledExprListSyntax(arguments)
        return ExprSyntax(rewritten)
    }
}

extension LayoutRewriter {
    func format(_ source: String) throws -> String {
        let parsed = Parser.parse(source: source)
        guard !parsed.hasError else {
            throw LayoutError.invalidSyntax
        }
        let rewritten = rewrite(parsed)
        guard parsed.tokens(viewMode: .sourceAccurate).map(\.tokenKind) == rewritten.tokens(viewMode: .sourceAccurate).map(\.tokenKind)
        else {
            throw LayoutError.changedTokens
        }
        guard comments(in: parsed) == comments(in: rewritten) else {
            throw LayoutError.changedComments
        }
        return rewritten.description
    }
}

private extension LayoutRewriter {
    func normalizedBoundary(_ trivia: Trivia) -> Trivia {
        var pieces = Array(trivia)
        while pieces.first?.isWhitespace == true {
            pieces.removeFirst()
        }
        while pieces.last?.isWhitespace == true {
            pieces.removeLast()
        }
        guard !pieces.isEmpty else {
            return .newline
        }
        return Trivia(pieces: [.newlines(1)] + pieces + [.newlines(1)])
    }

    func compactList<Element: CommaSeparatedElement>(
        _ elements: [Element],
        opening: inout TokenSyntax,
        closing: inout TokenSyntax
    ) -> [Element] {
        guard
            !(opening.trailingTrivia + closing.leadingTrivia).contains(where: \.isComment),
            elements.allSatisfy({ comments(in: $0).isEmpty && !$0.trimmedDescription.contains("\n") })
        else {
            return elements
        }
        opening.trailingTrivia = []
        closing.leadingTrivia = []
        return elements.map { element in
            var rewritten = element
            rewritten.leadingTrivia = []
            rewritten.trailingTrivia = []
            if var comma = rewritten.trailingComma {
                comma.leadingTrivia = []
                comma.trailingTrivia = .space
                rewritten.trailingComma = comma
            }
            return rewritten
        }
    }

    func comments(in syntax: some SyntaxProtocol) -> [String] {
        syntax.tokens(viewMode: .sourceAccurate).flatMap { token in
            (Array(token.leadingTrivia) + Array(token.trailingTrivia)).filter(\.isComment).map(\.debugDescription)
        }
    }
}

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let source = String(data: input, encoding: .utf8) else {
        throw LayoutError.invalidUTF8
    }
    let result = try LayoutRewriter().format(source)
    FileHandle.standardOutput.write(Data(result.utf8))
} catch {
    FileHandle.standardError.write(Data("Swift layout failed: \(error)\n".utf8))
    exit(1)
}
