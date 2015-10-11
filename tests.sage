"""Unit tests for weave.sage."""

from cStringIO import StringIO
from weave import parse_sage_expressions, Interpreter, SageWeaveSyntaxError, SageWeaveException
from sage.misc.sage_unittest import InstanceTester

def sageEval(x):
  return eval(preparse(x))


class SageExprTests(SageObject):
  def expect(self, tester, input, output):
    out = parse_sage_expressions(input, sageEval)
    tester.assertEqual(out, output)

  def _test_none(self, tester):
    self.expect(tester, "hello", "hello")

  def _test_end_of_string(self, tester):
    self.expect(tester, r"hello \sageexpr{'world'}",
                         "hello world")

  def _test_multiple(self, tester):
    self.expect(tester, r"\sageexpr{'hello'} \sageexpr{'world'}",
                         "hello world")

  def _test_fraction(self, tester):
    self.expect(tester, r"half is \sageexpr{2/4}",
                         "half is 1/2")

  def _test_fraction_latex(self, tester):
    self.expect(tester, r"half is \sageexpr{latex(2/4)}",
                        r"half is \frac{1}{2}")

  def _test_braces(self, tester):
    self.expect(tester, r"\sageexpr{'{}'}", "{}")
    self.expect(tester, r"\sageexpr{'}'}", "}")
    self.expect(tester, "\\sageexpr{'\"'}", '"')
    self.expect(tester, "\\sageexpr{\"'\"}", "'")


class InterpreterTests(SageObject):
  def do_weave(self, string):
    instream = StringIO(string)
    outstream = StringIO()
    interpreter = Interpreter(instream, outstream, 'test')
    interpreter.weave()
    return outstream.getvalue()

  def _test_print(self, tester):
    output = self.do_weave('line\n<<>>=\nprint "1/2"\n@')
    tester.assertEqual(output, 'line\n1/2\n')

  def _test_print_math(self, tester):
    output = self.do_weave('line\n<<>>=\nprint 2/4\n@')
    tester.assertEqual(output, 'line\n1/2\n')

  def _test_print_sageexpr(self, tester):
    output = self.do_weave('line\n<<>>=\nx = 2/4\n@\nHalf is \\sageexpr{x}.')
    tester.assertEqual(output, 'line\nHalf is \\frac{1}{2}.\n')

  def _test_print_sageexpr_newline(self, tester):
    output = self.do_weave('line\n<<>>=\nx = 2/4\n@\n\nHalf is \\sageexpr{x}.')
    tester.assertEqual(output, 'line\n\nHalf is \\frac{1}{2}.\n')

  def _test_syntaxError(self, tester):
    try:
      self.do_weave("line\n<<>>=\nbla//\n@")
    except SageWeaveSyntaxError, e:
      tester.assertEqual(e.message, 'SyntaxError: invalid syntax')
      tester.assertEqual(e.traceback(), '  File "test", line 3, in ?:\n>>>   3: bla//')
    else:
      tester.fail("Expected a SageWeaveSyntaxError")

  def _test_syntaxError_sageexpr(self, tester):
    try:
      self.do_weave("line\n\sageexpr{bla//}")
    except SageWeaveSyntaxError, e:
      tester.assertEqual(e.message, 'SyntaxError: unexpected EOF while parsing')
      tester.assertEqual(e.traceback(), '  File "test", line 2, in \\sageexpr{}:\n>>>   2: bla//')
    else:
      tester.fail("Expected a SageWeaveSyntaxError")

  def _test_exception(self, tester):
    expected = [
        '  File "test", line 6, in <module>:',
        '      3: def go():',
        '      4:   bla()',
        '      5: ',
        '>>>   6: go()',
        '  File "test", line 4, in go:',
        '      3: def go():',
        '>>>   4:   bla()',
        '      5: ',
        '      6: go()']
    try:
      self.do_weave("line\n<<>>=\ndef go():\n  bla()\n\ngo()\n@")
    except SageWeaveException, e:
      tester.assertEqual(e.message, "NameError: global name 'bla' is not defined")
      tester.assertEqual(e.traceback(), '\n'.join(expected))
    else:
      tester.fail("Expected a SageWeaveException")

  def _test_exception_sageexpr(self, tester):
    expected = [
        '  File "test", line 6, in \\sageexpr{}',
        '  File "test", line 4, in go:',
        '      3: def go():',
        '>>>   4:   bla()']

    try:
      self.do_weave("line\n<<>>=\ndef go():\n  bla()\n@\n\\sageexpr{go()}\n@")
    except SageWeaveException, e:
      tester.assertEqual(e.message, "NameError: global name 'bla' is not defined")
      tester.assertEqual(e.traceback(), "\n".join(expected))
    else:
      tester.fail("Expected a SageWeaveException")


TestSuite(SageExprTests()).run(skip ="_test_pickling")
TestSuite(InterpreterTests()).run(skip ="_test_pickling")

