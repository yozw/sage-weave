"""Unit tests for weave.sage."""

from weave import parse_sage_expressions
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


TestSuite(SageExprTests()).run(skip ="_test_pickling")

