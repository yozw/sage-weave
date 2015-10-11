#!/usr/local/bin/sage

import argparse
import os
import re
import sys
import traceback

from cStringIO import StringIO

AUTOGENERATE_MSG = [
    "%" + ("-" * 78),
    "% This file was *auto-generated* by sage-weave.",
    "% Do NOT edit unless you know what you are doing.",
    "%" + ("-" * 78),
    "%"
]


class LatexTokenReader(SageObject):
  QUOTE="'"
  DQUOTE='"'

  """Reads one LaTeX token."""
  def __init__(self):
    self.stack = []
    self.string = ""
    self.in_string = False
    
  def consume(self, char):
    if len(self.stack) > 0 and char == self.stack[-1]:
      del self.stack[-1]
      self.in_string = False
    elif not self.in_string and char == self.DQUOTE:
      self.stack.append(self.DQUOTE)
      self.in_string = True
    elif not self.in_string and char == self.QUOTE:
      self.stack.append(self.QUOTE)
      self.in_string = True
    elif not self.in_string and char == "{":
      self.stack.append("}")
    self.string = self.string + char
    return len(self.stack) > 0

  def readToken(self, string, start_index = 0):
    index = start_index
    sage_expr = ""
    while True:
      sage_expr += string[index]
      if not self.consume(string[index]):
        break
      index += 1
      if index >= len(string):
        raise Exception("Unexpected end of line")
    return sage_expr


def parse_sage_expressions(string, evalFn):
  """Takes a string and evaluates all \sageexpr{} expressions in it."""
  output = ""
  command = r'\sageexpr'
  while True:
    index = string.find(command)
    if index == -1:
      break
    reader = LatexTokenReader()
    sage_expr = reader.readToken(string, index + len(command))
    output += string[:index]
    output += str(evalFn(sage_expr[1:-1]))
    string = string[index + len(command) + len(sage_expr):]
    
  output += string
  return output


def delete_common_indentation(lines):
  """ Deletes any common indentation of a given list of strings, i.e., if all
  non-empty lines start with k spaces, the first k characters of each non-empty
  line are removed. """
  spaces = [len(line) - len(line.lstrip(' ')) for line in lines if len(line.strip()) > 0]
  if len(spaces) == 0: return lines
  start = min(spaces)
  if start == 0: return lines
  new_lines = []
  for line in lines:
    if line.strip() != "":
      line = line[start:]
    new_lines.append(line)
  return new_lines  


class Snippet:
  """ Code snippet embedded in weaved file. """
  last_snippet_id = [0]

  def __init__(self, code, line_no):
    self.code = code
    self.line_no = line_no
    self.last_snippet_id[0] += 1
    self.id = self.last_snippet_id[0]

  def format(self, mark = None):
    lines = []
    for i, line in enumerate(self.code):
      marker = ">>>" if i + 1 == mark else ""
      real_lineno = i + self.line_no + 1
      sys.stderr.write('%3s %3d: %s\n' % (marker, real_lineno, line))
    return "\n".join(lines) + "\n"


class Interpreter:
  """ Interpreter for Sage-weave files. """
  
  def __init__(self, input_stream, output_stream, scope):
    self.input_stream = input_stream
    self.output_stream = output_stream
    self.scope = scope
    self.line_no = 0
    self.snippets = {}
        
  def get_line(self):
    self.line_no += 1
    line = self.input_stream.readline()
    if not line: return None
    return line.rstrip('\n')
    
  def output(self, string):
    self.output_stream.write(string)

  def output_ln(self, string):
    self.output_stream.write(string)
    self.output_stream.write("\n")
    
  def get_snippet_from_id(self, id):
    """Gets the snippet with the given file id (of the form <sageweave#lineno>)."""
    match = re.search(r'<sageweave#(\d+)>', id)
    if match and match.lastindex:
      index = int(match.group(match.lastindex))
      return self.snippets[index]
    else:
      return None

  def print_trace(self, trace):
    """Prints stack trace (after exception)"""
    sys.stderr.write('Traceback:\n')
    for filename, lineno, func, _ in trace:
      trace_snippet = self.get_snippet_from_id(filename)
      if trace_snippet:
        real_lineno = lineno + trace_snippet.line_no
        sys.stderr.write('  Sage snippet #%d, line %d, in %s:\n' \
                         % (trace_snippet.id, real_lineno, func))
        sys.stderr.write(trace_snippet.format(mark = lineno))
      else:
        sys.stderr.write('  %s, line %d, in %s\n' % (filename, lineno, func))

  def weave_code(self):
    # Gather Sage code to be executed
    line_no_start = self.line_no
    code = []
    while True:
      line = self.get_line()
      if line == None:
        raise Exception("Unexpected end of file")
      if line.strip() == "@":
        break
      code.append(line)

    # Remove any common indentation
    code = delete_common_indentation(code)
    
    # Store snippet
    snippet = Snippet(code, line_no_start)
    self.snippets[snippet.id] = snippet

    # Pre-parse the Sage code into Python code
    preparsed_code = preparse("\n".join(code))

    # Compile Python code
    try:
      compiled_code = compile(preparsed_code, '<sageweave#%d>' % snippet.id, 'exec')
    except SyntaxError, e:
      sys.stderr.write("Syntax error while compiling code:\n")
      sys.stderr.write(snippet.format(mark = e.lineno))
      sys.stderr.write("Error: %s\n" % e)
      sys.exit(1)

    # Capture any output
    old_stdout = sys.stdout
    capture_stdout = StringIO()

    # Execute the Python code
    try:
      sys.stdout = capture_stdout
      exec(compiled_code, self.scope)
    except Exception, e:
      # Restore stdout
      sys.stdout = old_stdout

      # Print debug trace
      _, _, tb = sys.exc_info()
      trace = traceback.extract_tb(tb)[1:]
      self.print_trace(trace)
      sys.stderr.write("%s: %s\n" % (type(e).__name__, e.message))
      sys.exit(1)

    # Restore stdout
    sys.stdout = old_stdout
      
    # Write any output generated by the code to the output stream
    self.output(capture_stdout.getvalue())
    
  def weave_line(self, line):
    """Weaves one line by parse \sageexpr{} commands."""
    def evaluate(expr):
      try:
        return latex(eval(preparse(expr), self.scope))
      except SyntaxError, e:
        sys.stderr.write("Syntax error while evaluating Sage expression:\n")
        sys.stderr.write("  %s\n" % expr)
        sys.stderr.write("Error: %s\n" % e)
        sys.exit(1)
      except Exception, e:
        _, _, tb = sys.exc_info()
        trace = traceback.extract_tb(tb)[1:]
        sys.stderr.write("Exception while evaluating Sage expression:\n")
        sys.stderr.write("  %s\n" % expr)
        self.print_trace(trace)
        sys.stderr.write("%s: %s\n" % (type(e).__name__, e.message))
        sys.exit(1)

    return parse_sage_expressions(line, evaluate)
  
  def weave(self):
    while True:
      line = self.get_line()
      if line == None:
        return
      if line.strip().startswith("<<") and line.strip().endswith(">>="):
        self.weave_code()
      else:
        line = self.weave_line(line)
        self.output_ln(line)


def main(args):
  """ Sage-weave main entry point """
  
  # Override default output: - if input is -, else replace extension by .tex.
  if args.output == '':
    if args.input == '-':
      args.output = '-'
    else:
      (root, ext) = os.path.splitext(args.input)
      args.output = root + ".tex"
      # TODO: Check that the file either does not exist, or starts with the
      # 'autogenerated' header.

  # Open input stream
  input_stream = sys.stdin if args.input == "-" else open(args.input)

  # Open output stream
  output_stream = sys.stdout if args.output == "-" else open(args.output, "wt")
  
  # Output a warning stating that this file is auto-generated
  output_stream.write("\n".join(AUTOGENERATE_MSG))
  output_stream.write("\n")

  # Create an empty scope in which all embedded code will run
  scope = dict(globals())

  # Override the __file__ variable in the embedded scope
  scope["__file__"] = os.path.realpath(args.input) if args.input != "-" else "stdin"
  
  # Run the interpreter for the input stream
  try:
    interpreter = Interpreter(input_stream, output_stream, scope)
    interpreter.weave()
  finally:
    # Close the output file, if necessary
    if args.output != "-":
      output_stream.close()


if __name__ == "__main__":
  parser = argparse.ArgumentParser(
      description='Sage-weave is a tool for embedding Sage code in LaTeX documents.')
  parser.prog = "weave.sage"
  parser.add_argument('input', metavar='<input>',
                      nargs='?', default='-',
                      help='input file (- for stdin)')
  parser.add_argument('-o', dest='output',
                      default='',
                      help='output file (- for stdout)')

  args = parser.parse_args()    
  main(args)

