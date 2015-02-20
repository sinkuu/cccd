import std.d.ast;
import std.d.lexer;
import std.d.parser;

import std.algorithm;
import std.container.rbtree;
import std.exception;
import std.stdio;


StringCache cache = void;

static this()
{
    cache = StringCache(StringCache.defaultBucketCount);
}


int main(string[] args)
{
    import std.file;

    foreach (a; args[1 .. $])
    {
        if (isFile(a))
        {
            processFile(a);
        }
        else if (isDir(a))
        {
            import std.utf : byChar;
            foreach (f; dirEntries(a, SpanMode.breadth).filter!(f => f.name.byChar.endsWith(".d")))
            {
                processFile(f);
            }
        }
        else
        {
            stderr.writeln("cccd: ", a, ": No such file or directory");
        }
    }

    return 0;
}

void processFile(string filename)
{
    auto f = File(filename);
    auto bytes = new ubyte[](f.size);
    f.rawRead(bytes);

    auto tokens = getTokensForParser(bytes, LexerConfig(filename, StringBehavior.source), &cache);
    static void doNothing(string, size_t, size_t, string, bool) {}
    auto mod = parseModule(tokens, filename, null, &doNothing);

    auto visitor = new CCCounter;
    visitor.visit(mod);

    foreach (func; visitor.functions.sort!((a, b) => a.count > b.count))
    {
        writefln("%s:%s\t%s\t%s", filename, func.line, func.name, func.count);
    }
}

class CCCounter : ASTVisitor
{
    static struct Function
    {
        ulong line;
        string name;
        ulong count;

        bool opEquals(Function other) const @safe pure nothrow @nogc
        {
            return this.line == other.line && this.name == other.name;
        }
    }

    Function[] functions;
    Function[] stack;

    alias visit = ASTVisitor.visit;

    override void visit(const FunctionDeclaration functionDeclaration)
    {
        stack ~= Function(functionDeclaration.name.line,
                functionDeclaration.name.text,
                0);

        functionDeclaration.accept(this);

        functions ~= stack[$-1];
        stack = stack[0 .. $-1];
    }

    mixin template CountUpOn(T)
    {
        override void visit(const T node)
        {
            if (stack.length > 0) stack[$-1].count++;
            node.accept(this);
        }
    }

    mixin CountUpOn!IfStatement;
    mixin CountUpOn!WhileStatement;
    mixin CountUpOn!ForStatement;
    mixin CountUpOn!ForeachStatement;
    mixin CountUpOn!CaseStatement;
    mixin CountUpOn!CaseRangeStatement;
    mixin CountUpOn!DefaultStatement;
    mixin CountUpOn!ContinueStatement;
    mixin CountUpOn!GotoStatement;
    mixin CountUpOn!Catch;
    mixin CountUpOn!AndAndExpression;
    mixin CountUpOn!OrOrExpression;
    mixin CountUpOn!TernaryExpression;
}
