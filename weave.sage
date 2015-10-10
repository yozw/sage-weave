#!/usr/local/bin/sage

from cStringIO import StringIO
import os
import sys
import argparse

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


class Interpreter:
  """ Interpreter for Sage-weave files. """
  
  def __init__(self, input_stream, output_stream, scope):
    self.input_stream = input_stream
    self.output_stream = output_stream
    self.scope = scope
    self.line_no = 0
        
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
    
    # Pre-parse the Sage code into Python code
    preparsed_code = preparse("\n".join(code))
    
    # Capture any output
    old_stdout = sys.stdout
    capture_stdout = StringIO()

    sys.stderr.write("Running sage code starting at line %d.\n" % line_no_start)
    # Execute the Python code
    try:
      sys.stdout = capture_stdout
      exec preparsed_code in self.scope
    except e:
      # Restore stdout
      sys.stdout = old_stdout
      print "Exception was thrown:", e
      sys.exit(1)

    # Restore stdout
    sys.stdout = old_stdout
      
    # Write any output generated by the code to the output stream
    self.output(capture_stdout.getvalue())
    
  def weave_line(self, line):
    """Weaves one line by parse \sageexpr{} commands."""
    def evaluate(expr):
      return eval(preparse(expr), self.scope)
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
  
  # Open input stream
  input_stream = sys.stdin if args.input == "-" else open(args.input)

  # Open output stream
  output_stream = sys.stdout if args.output == "-" else open(args.output, "wt")
  
  # Output a warning stating that this file is auto-generated
  output_stream.write("%" + ("-" * 78) + "\n")
  output_stream.write("% This file was *auto-generated* by sage-weave from " + args.input + "\n")
  output_stream.write("% Do NOT edit unless you know what you are doing.\n")
  output_stream.write("%" + ("-" * 78) + "\n")
  output_stream.write("%\n")

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
  parser = argparse.ArgumentParser(description='Process some integers.')
  parser.add_argument('input', metavar='<input>', default='-', help='input file (- for stdin)')
  parser.add_argument('-o', dest='output', default='-', help='output file (- for stdout)')

  args = parser.parse_args()    
  main(args)

