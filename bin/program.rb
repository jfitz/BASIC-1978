# Contain line numbers
class LineNumber
  attr_reader :line_number

  def self.init?(text)
    /\A\d+\z/.match(text)
  end

  def initialize(line_number)
    raise BASICSyntaxError, "Invalid line number '#{line_number}'" unless
      line_number.class.to_s == 'NumericConstantToken'

    @line_number = line_number.to_i
  end

  def eql?(other)
    @line_number == other.line_number
  end

  def ==(other)
    @line_number == other.line_number
  end

  def hash
    @line_number.hash
  end

  def zero?
    @line_number.zero?
  end

  def succ
    LineNumber.new(@line_number + 1)
  end

  def <=>(other)
    @line_number <=> other.line_number
  end

  def >(other)
    @line_number > other.line_number
  end

  def >=(other)
    @line_number >= other.line_number
  end

  def <(other)
    @line_number < other.line_number
  end

  def <=(other)
    @line_number <= other.line_number
  end

  def dump
    self.class.to_s + ':' + @line_number.to_s
  end

  def to_s
    @line_number.to_s
  end

  def to_i
    @line_number
  end
end

# line number range, in form start-end
class LineNumberRange
  attr_reader :list

  def initialize(start, endline, program_line_numbers)
     @list = []
     program_line_numbers.each do |line_number|
      @list << line_number if line_number >= start && line_number <= endline
    end
  end
end

# line number range, in form start-count (count default is 20)
class LineNumberCountRange
  attr_reader :list

  def initialize(start, count, program_line_numbers)
    @list = []
    program_line_numbers.each do |line_number|
      if line_number >= start && count >= 0
        @list << line_number
        count -= 1
      end
    end
  end
end

# LineNumberIndex class to hold line number and index within line
class LineNumberIndex
  attr_reader :number
  attr_reader :statement
  attr_reader :index

  def initialize(number, statement, index)
    @number = number
    @statement = statement
    @index = index
  end

  def eql?(other)
    @number == other.number && @statement == other.statement && @index == other.index
  end

  def ==(other)
    @number == other.number && @statement == other.statement && @index == other.index
  end

  def hash
    @number.hash + @statement.hash + @index.hash
  end

  def to_s
    return @number.to_s if @statement.zero? && @index.zero?
    return @number.to_s + '.' + @statement.to_s if @index.zero?
    @number.to_s + '.' + @statement.to_s + '.' + @index.to_s
  end
end

# Line class to hold a line of code
class Line
  attr_reader :statements
  attr_reader :tokens

  def initialize(text, statements, tokens, comment)
    @text = text
    @statements = statements
    @tokens = tokens
    @comment = comment
  end

  def list
    @text
  end

  def pretty(multiline)
    if multiline
      pretty_lines = AbstractToken.pretty_multiline([], @tokens)
    else
      pretty_lines = [AbstractToken.pretty_tokens([], @tokens)]
    end

    unless @comment.nil?
      line_0 = pretty_lines[0]
      space = @text.size - (line_0.size + @comment.to_s.size)
      space = 5 if space < 5
      line_0 += ' ' * space
      line_0 += @comment.to_s
      pretty_lines[0] = line_0
    end

    pretty_lines
  end

  def parse
    texts = []
    @statements.each { |statement| texts << statement.dump }
  end

  def profile
    texts = []
    @statements.each { |statement| texts << statement.profile }
  end

  def renumber(renumber_map)
    tokens = []
    separator = StatementSeparatorToken.new('\\')
    @statements.each do |statement|
      statement.renumber(renumber_map)
      tokens << statement.keywords
      tokens << statement.tokens
      tokens << separator
    end
    tokens.pop
    text = AbstractToken.pretty_tokens([], tokens.flatten)
    Line.new(text, @statements, tokens.flatten, @comment)
  end

  def check(program, console_io, line_number)
    retval = true
    index = 0
    @statements.each do |statement|
      line_number_index = LineNumberIndex.new(line_number, index, 0)
      r = statement.program_check(program, console_io, line_number_index)
      retval &&= r
      index += 1
    end
    retval
  end
end

# line reference for cross reference
class LineRef
  def initialize(line_num, assignment)
    @line_num = line_num
    @assignment = assignment
  end

  def to_s
    if @assignment
      @line_num.to_s + '='
    else
      @line_num.to_s
    end
  end
end

# Contain line number ranges
# used in LIST and DELETE commands
class LineListSpec
  attr_reader :line_numbers
  attr_reader :range_type

  def initialize(tokens, program_line_numbers)
    @line_numbers = []
    @range_type = :empty

    if tokens.empty?
      @line_numbers = program_line_numbers
      @range_type = :all
    elsif tokens.size == 1 &&
          tokens[0].numeric_constant?
      make_single(tokens[0], program_line_numbers)
    elsif tokens.size == 3 &&
          tokens[0].numeric_constant? &&
          tokens[1].to_s == '-' &&
          tokens[2].numeric_constant?
      make_range(tokens, program_line_numbers)
    elsif tokens.size == 2 &&
          tokens[0].numeric_constant? &&
          tokens[1].to_s == '+'
      make_count_range(tokens, program_line_numbers)
    elsif tokens.size == 3 &&
          tokens[0].numeric_constant? &&
          tokens[1].to_s == '+' &&
          tokens[2].numeric_constant?
      make_count_range(tokens, program_line_numbers)
    else
      raise(BASICCommandError, 'Invalid list specification')
    end
  end

  private

  def make_single(token, program_line_numbers)
    line_number = LineNumber.new(token)
    @line_numbers << line_number if
      program_line_numbers.include?(line_number)
    @range_type = :single
  end

  def make_range(tokens, program_line_numbers)
    start = LineNumber.new(tokens[0])
    endline = LineNumber.new(tokens[2])
    range = LineNumberRange.new(start, endline, program_line_numbers)
    @line_numbers = range.list
    @range_type = :range
  end

  def make_count_range(tokens, program_line_numbers)
    start = LineNumber.new(tokens[0])
    count = 20
    count = NumericConstant.new(tokens[2]).to_i if tokens.size > 2
    range = LineNumberCountRange.new(start, count, program_line_numbers)
    @line_numbers = range.list
    @range_type = :range
  end
end

# program container
class Program
  attr_reader :lines

  def initialize(console_io, tokenbuilders)
    @console_io = console_io
    @lines = {}
    @errors = []
    @statement_factory = StatementFactory.instance
    @statement_factory.tokenbuilders = tokenbuilders
  end

  def empty?
    @lines.empty?
  end

  def line_number?(line_number)
    @lines.key?(line_number)
  end

  def first_line_number
    @lines.min[0]
  end

  def assign_function_markers
    user_function_lines = {}
    part_of_user_function = nil

    line_numbers = @lines.keys.sort

    line_numbers.each do |line_number|
      line = @lines[line_number]
      statements = line.statements
      statement_index = 0
      statements.each do |statement|
        if statement.multidef?
          function_name = statement.function_name
          line_index = LineNumberIndex.new(line_number, statement_index, 0)
          user_function_lines[function_name] = line_index
          part_of_user_function = function_name
        end

        statement.part_of_user_function = part_of_user_function

        part_of_user_function = nil if statement.multiend?

        statement_index += 1
      end
    end

    user_function_lines
  end

  private

  def check_program
    errors = []

    part_of_user_function = nil

    line_numbers = lines.keys.sort

    line_numbers.each do |line_number|
      line = @lines[line_number]
      statements = line.statements
      statements.each do |statement|
        if !part_of_user_function.nil? && statement.multidef?
          errors << "Missing FNEND before DEF in line #{line_number}"
        end

        if statement.multidef?
          function_name = statement.function_name
          part_of_user_function = function_name
        end

        part_of_user_function = nil if statement.multiend?
      end
    end

    errors
  end

  def line_list_spec(tokens)
    line_numbers = @lines.keys.sort
    LineListSpec.new(tokens, line_numbers)
  end

  public

  def cmd_new
    @lines = {}
    @errors = check_program
  end

  def list(args, list_tokens)
    line_number_range = line_list_spec(args)

    if !@lines.empty?
      line_numbers = line_number_range.line_numbers
      list_lines_errors(line_numbers, list_tokens)
      @errors.each { |error| @console_io.print_line(error) }
    else
      @console_io.print_line('No program loaded')
    end
  end

  def parse(args)
    line_number_range = line_list_spec(args)

    if !@lines.empty?
      line_numbers = line_number_range.line_numbers
      parse_lines_errors(line_numbers)
    else
      @console_io.print_line('No program loaded')
    end
  end

  def pretty(args, pretty_multiline)
    line_number_range = line_list_spec(args)

    if !@lines.empty?
      line_numbers = line_number_range.line_numbers
      pretty_lines_errors(line_numbers, pretty_multiline)
      @errors.each { |error| @console_io.print_line(error) }
    else
      @console_io.print_line('No program loaded')
    end
  end

  private

  def reset_profile_metrics
    @lines.keys.sort.each do |line_number|
      line = @lines[line_number]
      statements = line.statements
      statements.each do |statement|
        statement.reset_profile_metrics
      end
    end
  end

  public

  def preexecute_loop(interpreter)
    okay = true

    @lines.keys.sort.each do |line_number|
      line = @lines[line_number]
      @line_number = line_number
      statements = line.statements
      statements.each do |statement|
        okay &=
          statement.preexecute_a_statement(line_number, interpreter, @console_io)
      end
    end

    okay
  rescue BASICRuntimeError => e
    message = "#{e.message} in line #{@line_number}"
    @console_io.print_line(message)
    false
  end

  def find_closing_next(control_variable, current_line_index)
    # move to the next statement
    line_number = current_line_index.number
    line = @lines[line_number]
    statements = line.statements
    statement_index = current_line_index.statement + 1
    line_numbers = @lines.keys.sort

    if statement_index < statements.size
      forward_line_numbers =
        line_numbers.select { |ln| ln >= current_line_index.number }
    else
      forward_line_numbers =
        line_numbers.select { |ln| ln > current_line_index.number }
    end

    # search for a NEXT with the same control variable
    until forward_line_numbers.empty?
      line_number = forward_line_numbers[0]
      line = @lines[line_number]
      statements = line.statements
      statement_index = 0
      statements.each do |statement|
        # consider only core statements, not modifiers
        return LineNumberIndex.new(line_number, statement_index, 0) if
          statement.class.to_s == 'NextStatement' &&
          statement.has_control(control_variable)
        statement_index += 1
      end

      forward_line_numbers.shift
    end

    # if none found, error
    raise(BASICRuntimeError, 'FOR without NEXT')
  end

  def run(interpreter)
    if @lines.empty?
      @console_io.print_line('No program loaded')
      return
    end

    unless @errors.empty?
      @errors.each { |error| @console_io.print_line(error) }
      return
    end

    reset_profile_metrics
    interpreter.run(self)
  end

  def profile(args)
    line_number_range = line_list_spec(args)

    if @lines.empty?
      @console_io.print_line('No program loaded')
      return
    end

    line_numbers = line_number_range.line_numbers
    profile_lines_errors(line_numbers)
  end

  private

  def load_file(filename)
    File.open(filename, 'r') do |file|
      @lines = {}
      file.each_line do |line|
        line = @console_io.ascii_printables(line)
        store_program_line(line, false)
      end
    end
    true
  rescue Errno::ENOENT
    @console_io.print_line("File '#{filename}' not found")
    false
  end

  public

  def load(tokens)
    if tokens.empty?
      @console_io.print_line('Filename not specified')
      return false
    end

    if tokens.size > 1
      @console_io.print_line('Too many items specified')
      return false
    end

    token = tokens[0]

    unless token.text_constant?
      @console_io.print_line('File name must be quoted literal')
      return false
    end

    filename = token.value.strip
    if filename.empty?
      @console_io.print_line('Filename not specified')
      return false
    end

    r = load_file(filename)
    @errors = check_program
    r
  end

  private

  def save_file(filename)
    line_numbers = @lines.keys.sort
    begin
      File.open(filename, 'w') do |file|
        line_numbers.each do |line_num|
          line = @lines[line_num]
          file.puts line_num.to_s + line.list
        end
        file.close
      end
    rescue Errno::ENOENT
      @console_io.print_line("File '#{filename}' not opened")
    end
  end

  public

  def save(tokens)
    if tokens.empty?
      @console_io.print_line('Filename not specified')
      return false
    end

    if tokens.size > 1
      @console_io.print_line('Too many items specified')
      return false
    end

    token = tokens[0]

    unless token.text_constant?
      @console_io.print_line('File name must be text')
      return false
    end

    filename = token.value.strip
    if filename.empty?
      @console_io.print_line('Filename not specified')
      return false
    end

    if @lines.empty?
      @console_io.print_line('No program loaded')
      return false
    end

    save_file(filename)
  end

  def print_profile
    @lines.keys.sort.each do |line_number|
      line = @lines[line_number]
      number = line_number.to_s
      statements = line.statements
      statement_index = 0
      statements.each do |statement|
        profile = statement.profile
        text = number.to_s + '.' + statement_index.to_s + profile
        @console_io.print_line(text)
        statement_index += 1
      end
    end
  end

  def delete(args)
    line_number_range = line_list_spec(args)

    raise(BASICCommandError, 'No program loaded') if
      @lines.empty?

    raise(BASICCommandError, 'Type NEW to delete an entire program') if
      line_number_range.range_type == :all

    line_numbers = line_number_range.line_numbers
    delete_specific_lines(line_numbers)
    @errors = check_program
  end

  def enblank(args)
    line_number_range = line_list_spec(args)

    raise(BASICCommandError, 'No program loaded') if
      @lines.empty?

    raise(BASICCommandError, 'You cannot delete an entire program') if
      line_number_range.range_type == :all

    line_numbers = line_number_range.line_numbers
    enblank_specific_lines(line_numbers)
  end

  # generate new line numbers
  def renumber
    renumber_map = {}
    new_number = 10

    @lines.keys.sort.each do |line_number|
      number_token = NumericConstantToken.new(new_number)
      new_line_number = LineNumber.new(number_token)
      renumber_map[line_number] = new_line_number
      new_number += 10
    end

    # assign new line numbers
    new_lines = {}
    @lines.keys.sort.each do |line_number|
      line = @lines[line_number]
      new_line_number = renumber_map[line_number]
      new_lines[new_line_number] = line.renumber(renumber_map)
    end

    @lines = new_lines
    @errors = check_program
    renumber_map
  end

  private

  def numeric_refs
    refs = {}

    @lines.keys.sort.each do |line_number|
      line = @lines[line_number]
      statements = line.statements

      rs = []
      statements.each do |statement|
        rs += statement.numerics
      end
      refs[line_number] = rs
    end

    refs
  end

  def text_refs
    refs = {}

    @lines.keys.sort.each do |line_number|
      line = @lines[line_number]
      statements = line.statements

      rs = []
      statements.each do |statement|
        rs += statement.strings
      end
      refs[line_number] = rs
    end

    refs
  end

  def function_refs
    refs = {}

    @lines.keys.sort.each do |line_number|
      line = @lines[line_number]
      statements = line.statements

      rs = []
      statements.each do |statement|
        rs = statement.functions
      end
      refs[line_number] = rs
    end

    refs
  end

  def user_function_refs
    refs = {}

    @lines.keys.sort.each do |line_number|
      line = @lines[line_number]
      statements = line.statements

      rs = []
      statements.each do |statement|
        rs += statement.userfuncs
      end
      refs[line_number] = rs
    end

    refs
  end

  def variables_refs
    refs = {}

    @lines.keys.sort.each do |line_number|
      line = @lines[line_number]
      statements = line.statements

      rs = []
      statements.each do |statement|
        rs.concat statement.variables
      end
      refs[line_number] = rs
    end

    refs
  end

  def print_refs(title, refs)
    @console_io.print_line(title)

    refs.keys.sort.each do |ref|
      lines = refs[ref]
      line = ref + ":\t" + lines.map(&:to_s).uniq.join(', ')
      @console_io.print_line(line)
    end

    @console_io.print_line('')
  end

  def print_num_refs(title, refs)
    @console_io.print_line(title)

    refs.keys.sort.each do |ref|
      lines = refs[ref]
      line = ref.to_s + ":\t" + lines.map(&:to_s).uniq.join(', ')
      @console_io.print_line(line)
    end

    @console_io.newline
  end

  def make_summary(list)
    summary = {}

    list.each do |line_number, refs|
      line_ref = LineRef.new(line_number, false)
      refs.each do |ref|
        entries = summary.key?(ref) ? summary[ref] : []
        entries << line_ref
        summary[ref] = entries
      end
    end

    summary
  end

  public

  # generate cross-reference list
  def crossref
    @console_io.print_line('Cross reference')
    @console_io.newline

    nums_list = numeric_refs
    numerics = make_summary(nums_list)
    print_num_refs('Numeric constants', numerics)

    strs_list = text_refs
    strings = make_summary(strs_list)
    print_num_refs('String constants', strings)

    funcs_list = function_refs
    functions = make_summary(funcs_list)
    print_refs('Functions', functions)

    udfs_list = user_function_refs
    userfuncs = make_summary(udfs_list)
    print_refs('User-defined functions', userfuncs)

    vars_list = variables_refs
    variables = make_summary(vars_list)
    print_refs('Variables', variables)
  end

  private

  def parse_line(line)
    @statement_factory.parse(line)
  rescue BASICError => e
    @console_io.print_line("Syntax error: #{e.message}")
  end

  def check_line_duplicate(line_num, print_errors)
    # warn about duplicate lines when loading
    # but not when typing
    @console_io.print_line("Duplicate line number #{line_num}") if
      @lines.key?(line_num) && !print_errors
  end

  def check_line_sequence(line_num, print_errors)
    # warn about lines out of sequence
    # but not when typing
    @console_io.print_line("Line #{line_num} is out of sequence") if
      !@lines.empty? &&
      line_num < @lines.max[0] &&
      !print_errors
  end

  public

  def store_program_line(cmd, print_errors)
    line_num, line = parse_line(cmd)

    if !line_num.nil? && !line.nil?
      check_line_duplicate(line_num, print_errors)
      check_line_sequence(line_num, print_errors)
      @lines[line_num] = line
      statements = line.statements
      any_errors = false
      statements.each do |statement|
        statement.errors.each { |error| @console_io.print_line(error) } if
          print_errors

        any_errors |= !statement.errors.empty?
      end
      @errors = check_program
      any_errors
    else
      true
    end
  end

  private

  def list_lines_errors(line_numbers, list_tokens)
    line_numbers.each do |line_number|
      line = @lines[line_number]

      # print the line
      @console_io.print_line(line_number.to_s + line.list)
      statements = line.statements

      # print the errors
      statements.each do |statement|
        statement.errors.each { |error| @console_io.print_line(' ' + error) }
      end

      next unless list_tokens

      tokens = line.tokens
      text_tokens = tokens.map(&:to_s)
      @console_io.print_line('TOKENS: ' + text_tokens.to_s)
    end
  end

  def parse_lines_errors(line_numbers)
    line_numbers.each do |line_number|
      line = @lines[line_number]

      # print the line
      @console_io.print_line(line_number.to_s + line.list)
      statements = line.statements

      # print the errors
      statements.each do |statement|
        statement.errors.each { |error| @console_io.print_line(' ' + error) }
      end

      # print the line components
      statements.each do |statement|
        texts = statement.dump
        texts.each { |text| @console_io.print_line(' ' + text) }
      end
    end
  end

  def pretty_lines_errors(line_numbers, pretty_multiline)
    line_numbers.each do |line_number|
      line = @lines[line_number]

      # print the line
      number = line_number.to_s
      pretty_lines = line.pretty(pretty_multiline)
      pretty_lines.each do |pretty_line|
        @console_io.print_line(number + pretty_line)
        number = ' ' * number.size
      end

      # print the errors
      statements = line.statements
      statements.each do |statement|
        statement.errors.each { |error| @console_io.print_line(' ' + error) }
      end
    end
  end

  def profile_lines_errors(line_numbers)
    line_numbers.each do |line_number|
      line = @lines[line_number]
      number = line_number.to_s
      statements = line.statements
      statement_index = 0
      statements.each do |statement|
        profile = statement.profile
        @console_io.print_line(number + '.' + statement_index.to_s + profile)
        statement_index += 1
      end
    end
  end

  def list_lines(line_numbers)
    line_numbers.each do |line_number|
      line = @lines[line_number]
      text = line.list
      @console_io.print_line(line_number.to_s + text)
    end
  end

  def list_and_delete_lines(line_numbers)
    list_lines(line_numbers)
    print 'DELETE THESE LINES? '
    answer = @console_io.read_line
    delete_specific_lines(line_numbers) if answer == 'YES'
  end

  def delete_specific_lines(line_numbers)
    line_numbers.each { |line_number| @lines.delete(line_number) }
  end

  def enblank_specific_lines(line_numbers)
    line_numbers.each do |line_number|
      blank_line = line_number.to_s
      line_num, line = @statement_factory.parse(blank_line)
      @lines[line_num] = line
    end
  end

  public

  def check
    result = true

    @lines.keys.sort.each do |line_number|
      r = @lines[line_number].check(self, @console_io, line_number)
      result &&= r
    end

    result
  end

  def find_next_line_index(current_line_index)
    # find next index with current statement
    line_number = current_line_index.number
    line = @lines[line_number]

    statements = line.statements
    statement_index = current_line_index.statement
    statement = statements[statement_index]

    index = current_line_index.index

    if index < statement.last_index
      index += 1
      return LineNumberIndex.new(line_number, statement_index, index)
    end

    # find next statement within the current line
    if statement_index < statements.size - 1
      statement_index += 1
      statement = statements[statement_index]
      index = statement.start_index
      return LineNumberIndex.new(line_number, statement_index, index)
    end

    # find the next line
    line_numbers = @lines.keys.sort
    line_number = current_line_index.number
    index = line_numbers.index(line_number)
    line_number = line_numbers[index + 1]

    unless line_number.nil?
      line = @lines[line_number]
      statements = line.statements
      statement = statements[0]
      index = statement.start_index
      return LineNumberIndex.new(line_number, 0, index)
    end

    # nothing left to execute
    nil
  end

  def find_next_line(current_line_index)
    # find next numbered statement
    line_numbers = @lines.keys.sort
    line_number = current_line_index.number
    index = line_numbers.index(line_number)
    line_number = line_numbers[index + 1]

    unless line_number.nil?
      line = @lines[line_number]
      statements = line.statements
      statement = statements[0]
      index = statement.start_index
      next_line_index = LineNumberIndex.new(line_number, 0, index)
      return next_line_index
    end

    # nothing left to execute
    nil
  end
end
