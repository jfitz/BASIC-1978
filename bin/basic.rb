#!/usr/bin/ruby

require 'benchmark'
require 'optparse'
require 'singleton'

require_relative 'exceptions'
require_relative 'tokens'
require_relative 'tokenbuilders'
require_relative 'tokenizers'
require_relative 'constants'
require_relative 'operators'
require_relative 'functions'
require_relative 'expressions'
require_relative 'io'
require_relative 'statements'
require_relative 'modifiers'
require_relative 'interpreter'
require_relative 'program'

# option class
class Option
  attr_reader :types

  def initialize(types, defs, value)
    @types = types
    @defs = defs
    check_value(value)
    @values = [value]
  end

  def set(value)
    num_types = %w[Fixnum Integer]
    if @defs[:type] == :bool && num_types.include?(value.class.to_s)
      value = value != 0
    end

    check_value(value)
    @values = [value]
  end

  def value
    @values[-1]
  end

  def push(value)
    num_types = %w[Fixnum Integer]
    if @defs[:type] == :bool && num_types.include?(value.class.to_s)
      value = value != 0
    end

    check_value(value)
    @values.push(value)
  end

  def pop
    @values.pop if @values.size > 1
  end

  def to_s
    v = value
    case @defs[:type]
    when :bool
      v.to_s
    when :int
      v.to_s
    when :float
      v.to_s
    when :string
      '"' + v.to_s + '"'
    when :list
      '"' + v.to_s + '"'
    end
  end

  private

  def check_value(value)
    check_value_and_type(value)
  rescue BASICSyntaxError => e
    raise e unless @defs.key?(:off) && value == @defs[:off]
  end

  def check_value_and_type(value)
    type = @defs[:type]
    case type
    when :bool
      legals = %w[TrueClass FalseClass]

      raise(BASICSyntaxError, "Invalid type #{value.class} for boolean") unless
        legals.include?(value.class.to_s)
    when :int
      legals = %w[Fixnum Integer]

      raise(BASICSyntaxError, "Invalid type #{value.class} for integer") unless
        legals.include?(value.class.to_s)

      min = @defs[:min]
      if !min.nil? && value < min
        raise(BASICSyntaxError, "Value #{value} below minimum #{min}")
      end

      max = @defs[:max]
      if !max.nil? && value > max
        raise(BASICSyntaxError, "Value #{value} above maximum #{max}")
      end
    when :float
      legals = %w[Fixnum Integer Float Rational]

      raise(BASICSyntaxError, "Invalid type #{value.class} for float") unless
        legals.include?(value.class.to_s)

      min = @defs[:min]
      if !min.nil? && value < min
        raise(BASICSyntaxError, "Value #{value} below minimum #{min}")
      end

      max = @defs[:max]
      if !max.nil? && value > max
        raise(BASICSyntaxError, "Value #{value} above maximum #{max}")
      end
    when :string
      legals = %(String)

      raise(BASICSyntaxError, "Invalid type #{value.class} for string") unless
        legals.include?(value.class.to_s)
    when :list
      legal_types = %(String)

      raise(BASICSyntaxError, "Invalid type #{value.class} for list") unless
        legal_types.include?(value.class.to_s)

      legal_values = @defs[:values]

      raise(BASICSyntaxError, "Invalid value #{value} for list #{legal_values}") unless
        legal_values.include?(value.to_s)
    else
      raise(BASICSyntaxError, 'Unknown value type')
    end
  end
end

# interactive shell
class Shell
  def initialize(console_io, interpreter, tokenbuilders)
    @console_io = console_io
    @interpreter = interpreter
    @tokenbuilders = tokenbuilders
    @invalid_tokenbuilder = InvalidTokenBuilder.new
  end

  def run
    need_prompt = true
    @done = false

    until @done
      prompt = $options['prompt'].value
      if need_prompt
        @console_io.print_item(prompt)
        @console_io.newline if prompt.size > 1
      end
      cmd = @console_io.read_line
      need_prompt = process_line_keyboard(cmd)
      need_prompt = true if prompt.size == 1
    end
  end

  private

  def process_line_keyboard(line)
    # starts with a number, so maybe it is a program line
    return @interpreter.program_store_line(line, false, true) if
      /\A[ \t]*\d/ =~ line

    # immediate command -- tokenize and execute
    tokenizer = Tokenizer.new(@tokenbuilders, @invalid_tokenbuilder)
    tokens = tokenizer.tokenize(line)
    tokens.delete_if(&:whitespace?)

    process_command_keyboard(tokens, line)
  end

  def process_command_keyboard(tokens, line)
    return false if tokens.empty?

    keyword = tokens[0]
    args = tokens[1..-1]

    if keyword.keyword?
      execute_command(keyword, args)
    else
      @console_io.print_line("Unknown command '#{line}'")
      @console_io.newline
    end
  end

  def process_line_load_command(line)
    return if line.empty?

    # starts with a '.', so is an immediate command
    if line[0] == '.'
      tokenizer = Tokenizer.new(@tokenbuilders, @invalid_tokenbuilder)
      nline = line[1..-1]
      tokens = tokenizer.tokenize(nline)
      tokens.delete_if(&:whitespace?)

      process_command_load_command(tokens, line)
      return
    end

    # starts with a number, so maybe it is a program line
    return @interpreter.program_store_line(line, true, true) if
      /\A[ \t]*\d/ =~ line

    # unknown line (probably a continuation of previous line)
    @console_io.print_line("Unknown command '#{line}'")
    @console_io.newline
  end

  def process_command_load_command(tokens, line)
    return false if tokens.empty?

    keyword = tokens[0]
    args = tokens[1..-1]

    if keyword.keyword?
      execute_command_load_command(keyword, args)
    else
      @console_io.print_line("Unknown command '#{line}'")
      @console_io.newline
    end
  end

  def option_command(args, echo_set)
    lines = []

    if args.empty?
      $options.each do |option|
        name = option[0].upcase
        value = option[1].to_s.upcase
        lines << 'OPTION ' + name + ' ' + value
      end
    elsif args.size == 1 && args[0].keyword?
      kwd = args[0].to_s
      kwd_d = kwd.downcase

      if $options.key?(kwd_d)
        value = $options[kwd_d].to_s.upcase
        lines << 'OPTION ' + kwd + ' ' + value.to_s if echo_set
      else
        raise BASICCommandError.new("Unknown option #{kwd}")
      end
    elsif args.size == 2 && args[0].keyword?
      kwd = args[0].to_s
      kwd_d = kwd.downcase

      raise BASICCommandError.new("Unknown option #{kwd}") unless
        $options.key?(kwd_d)

      if @interpreter.program_loaded? &&
         !$options[kwd_d].types.include?(:loaded)
        raise BASICCommandError.new("Cannot change #{kwd} when program is loaded")
      end

      if args[1].boolean_constant?
        boolean = BooleanConstant.new(args[1])
        $options[kwd_d].set(boolean.to_v)
      elsif args[1].numeric_constant?
        numeric = NumericConstant.new(args[1])
        $options[kwd_d].set(numeric.to_v)
      elsif args[1].text_constant?
        text = TextConstant.new(args[1])
        $options[kwd_d].set(text.to_v)
      else
        raise BASICCommandError.new('Incorrect value type')
      end

      value = $options[kwd_d].value.to_s.upcase
      lines << 'OPTION ' + kwd + ' ' + value
    else
      raise BASICCommandError.new('Too many arguments')
    end

    lines
  end

  def duplicate(o)
    Marshal.load(Marshal.dump(o))
  end

  def execute_command(keyword, args)
    need_prompt = true

    case keyword.to_s
    when 'EXIT'
      @done = true
    when 'NEW'
      @interpreter.program_new
      @interpreter.clear_variables
      @interpreter.clear_all_breakpoints
      @console_io.newline
    when 'RUN'
      if @interpreter.program_okay?
        # duplicate the options
        options2 = {}
        $options.each { |name, option| options2[name] = duplicate(option) }

        timing = Benchmark.measure do
          @interpreter.run
        end

        # restore options to undo any changes during the run
        options2.each { |name, option| $options[name] = option }

        # print timing info
        if $options['timing'].value
          print_timing(timing, @console_io)
          @console_io.newline
        end
      end
    when 'BREAK'
      texts = @interpreter.set_breakpoints(args)
      texts.each { |text| @console_io.print_line(text) }
    when 'NOBREAK'
      texts = @interpreter.clear_breakpoints(args)
      texts.each { |text| @console_io.print_line(text) }
    when 'LOAD'
      @interpreter.clear_all_breakpoints
      filename, _keywords = parse_args(args)

      raise BASICCommandError.new('Filename not specified') if filename.nil?

      load_file_keyboard(filename)

      @interpreter.print_program_errors
      @console_io.newline
    when 'SAVE'
      filename, keywords = parse_args(args)

      raise BASICCommandError.new('Filename not specified') if filename.nil?

      lines = []

      if keywords.include?('OPTION')
        option_lines = option_command([], false)
        option_lines.each do |line|
          lines << '.' + line
        end
      end

      lines += @interpreter.program_save

      if keywords.include?('BREAK')
        break_lines = @interpreter.set_breakpoints([])
        break_lines.each do |line|
          lines << '.' + line
        end
      end

      save_file(filename, lines)
    when 'LIST'
      texts = @interpreter.program_list(args, false)
      texts.each { |text| @console_io.print_line(text) }
      @interpreter.print_program_errors
      @console_io.newline
    when 'PRETTY'
      pretty_multiline = $options['pretty_multiline'].value
      texts = @interpreter.program_pretty(args, pretty_multiline)
      texts.each { |text| @console_io.print_line(text) }
      @interpreter.print_program_errors
      @console_io.newline
    when 'DELETE'
      @interpreter.program_delete(args)
    when 'PROFILE'
      show_timing = $options['timing'].value
      texts = @interpreter.program_profile(args, show_timing)
      texts.each { |text| @console_io.print_line(text) }
      @interpreter.print_program_errors
      @console_io.newline
    when 'RENUMBER'
      begin
        @interpreter.program_renumber(args) if @interpreter.program_okay?
      rescue BASICCommandError, BASICSyntaxError => e
        @console_io.print_line("Cannot renumber the program: #{e}")
      end
      @interpreter.print_program_errors
      @console_io.newline
    when 'CROSSREF'
      if @interpreter.program_okay?
        texts = @interpreter.program_crossref
        texts.each { |text| @console_io.print_line(text) }
      else
        @interpreter.print_program_errors
      end
    when 'DIMS'
      @interpreter.dump_dims
    when 'PARSE'
      texts = @interpreter.program_parse(args)
      texts.each { |text| @console_io.print_line(text) }
      @interpreter.print_program_errors
      @console_io.newline
    when 'ANALYZE'
      if @interpreter.program_okay?
        texts = @interpreter.program_analyze
        texts.each { |text| @console_io.print_line(text) }
      else
        @interpreter.print_program_errors
      end
    when 'TOKENS'
      texts = @interpreter.program_list(args, true)
      texts.each { |text| @console_io.print_line(text) }
      @console_io.newline
    when 'UDFS'
      @interpreter.dump_user_functions
    when 'VARS'
      @interpreter.dump_vars
    when 'OPTION'
      texts = option_command(args, true)
      texts.each { |text| @console_io.print_line(text) }
      @console_io.newline
    else
      @console_io.print_line("Unknown command #{keyword}")
      @console_io.newline
    end

    need_prompt
  rescue BASICCommandError, BASICRuntimeError, BASICSyntaxError => e
    @console_io.print_line(e.to_s)
    @console_io.newline
    true
  end

  def execute_command_load_command(keyword, args)
    need_prompt = true

    case keyword.to_s
    when 'BREAK'
      texts = @interpreter.set_breakpoints(args)
      texts.each { |text| @console_io.print_line(text) }
    when 'OPTION'
      texts = option_command(args, false)
      texts.each { |text| @console_io.print_line(text) }
    else
      @console_io.print_line("Unknown command #{keyword}")
    end

    need_prompt
  rescue BASICCommandError, BASICRuntimeError, BASICSyntaxError => e
    line = keyword.to_s + ' ' + args.map(&:to_s).join(' ')
    @console_io.print_line(line)
    @console_io.print_line(e.to_s)
    @console_io.newline
    true
  end

  def load_file_keyboard(filename)
    File.open(filename, 'r') do |file|
      @interpreter.program_clear
      file.each_line do |line|
        line = @console_io.ascii_printables(line)
        process_line_load_command(line)
      end
    end
  rescue Errno::ENOENT, Errno::EISDIR
    @console_io.print_line("File '#{filename}' not found")
  end

  def save_file(filename, lines)
    File.open(filename, 'w') do |file|
      lines.each do |line|
        file.puts line
      end
      file.close
    end
  rescue Errno::ENOENT, Errno::EISDIR
    @console_io.print_line("File '#{filename}' not saved")
  end
end

def make_interpreter_tokenbuilders(options, quotes, statement_separators,
                                   comment_leads)
  tokenbuilders = []

  tokenbuilders << CommentTokenBuilder.new(comment_leads)
  tokenbuilders << RemarkTokenBuilder.new

  unless statement_separators.empty?
    tokenbuilders <<
      ListTokenBuilder.new(statement_separators, StatementSeparatorToken)
  end

  statement_factory = StatementFactory.instance
  keywords = statement_factory.keywords_definitions
  tokenbuilders << ListTokenBuilder.new(keywords, KeywordToken)

  un_ops = UnaryOperator.operators
  bi_ops = BinaryOperator.operators
  operators = (un_ops + bi_ops).uniq
  tokenbuilders << ListTokenBuilder.new(operators, OperatorToken)

  tokenbuilders << ListTokenBuilder.new(['('], GroupStartToken)
  tokenbuilders << ListTokenBuilder.new([')'], GroupEndToken)
  tokenbuilders << ListTokenBuilder.new([',', ';'], ParamSeparatorToken)

  tokenbuilders <<
    ListTokenBuilder.new(FunctionFactory.function_names, FunctionToken)

  tokenbuilders <<
    ListTokenBuilder.new(FunctionFactory.user_function_names, UserFunctionToken)

  tokenbuilders << TextTokenBuilder.new(quotes)
  tokenbuilders << NumberTokenBuilder.new
  tokenbuilders << NumericSymbolTokenBuilder.new
  tokenbuilders << IntegerTokenBuilder.new

  long_names = options['long_names'].value
  tokenbuilders << VariableTokenBuilder.new(long_names)
  tokenbuilders << ListTokenBuilder.new(%w[TRUE FALSE], BooleanConstantToken)
  tokenbuilders << WhitespaceTokenBuilder.new
end

def make_command_tokenbuilders(quotes, long_names)
  tokenbuilders = []

  keywords = %w[
    ANALYZE BREAK NOBREAK CROSSREF DELETE DIMS EXIT IF LIST LOAD NEW OPTION
    PARSE PRETTY PROFILE RENUMBER RUN SAVE TOKENS UDFS VARS
    APOSTROPHE_COMMENT ASC_ALLOW_ALL
    BACK_TAB BASE
    CACHE_CONST_EXPR CHR_ALLOW_ALL
    DEFAULT_PROMPT DETECT_INFINITE_LOOP
    ECHO EXTEND_IF FIELD_SEP FORGET_FORNEXT HEADING
    IF_FOR_SUB IGNORE_RND_ARG IMPLIED_SEMICOLON
    INT_BITWISE INT_FLOOR LOCK_FORNEXT LONG_NAMES
    MAX_DIM MAX_LINE_NUM MIN_LINE_NUM
    NEWLINE_SPEED
    PRECISION PRETTY_MULTILINE PRINT_SPEED PRINT_WIDTH
    PROMPT PROMPTD PROMPT_COUNT PROVENANCE
    QMARK_AFTER_PROMPT RANDOMIZE RELATIONAL_BOOLEAN
    REQUIRE_INITIALIZED RESPECT_RANDOMIZE
    SEMICOLON_ZONE_WIDTH TIMING TRACE WRAP ZONE_WIDTH
  ]
  tokenbuilders << ListTokenBuilder.new(keywords, KeywordToken)

  un_ops = UnaryOperator.operators
  bi_ops = BinaryOperator.operators
  operators = (un_ops + bi_ops).uniq
  tokenbuilders << ListTokenBuilder.new(operators, OperatorToken)

  tokenbuilders << ListTokenBuilder.new(['('], GroupStartToken)
  tokenbuilders << ListTokenBuilder.new([')'], GroupEndToken)
  tokenbuilders << ListTokenBuilder.new([',', ';'], ParamSeparatorToken)

  tokenbuilders <<
    ListTokenBuilder.new(FunctionFactory.function_names, FunctionToken)

  tokenbuilders <<
    ListTokenBuilder.new(FunctionFactory.user_function_names, UserFunctionToken)

  tokenbuilders << TextTokenBuilder.new(quotes)

  tokenbuilders << NumberTokenBuilder.new
  tokenbuilders << VariableTokenBuilder.new(long_names)
  tokenbuilders << ListTokenBuilder.new(%w[TRUE FALSE], BooleanConstantToken)
  tokenbuilders << WhitespaceTokenBuilder.new
end

def print_timing(timing, console_io)
  user_time = timing.utime + timing.cutime
  sys_time = timing.stime + timing.cstime
  console_io.print_line('CPU time:')
  console_io.print_line(" user: #{user_time.round(2)}")
  console_io.print_line(" system: #{sys_time.round(2)}")
end

def parse_args(tokens)
  filename = nil
  keywords = []

  tokens.each do |token|
    keywords << token if token.keyword?
    filename = token.value.strip if token.text_constant? && filename.nil?
  end

  [filename, keywords]
end

def load_file_command_line(filename, interpreter, console_io)
  File.open(filename, 'r') do |file|
    interpreter.program_clear
    file.each_line do |line|
      line = console_io.ascii_printables(line)
      interpreter.program_store_line(line, false, false)
    end
  end
  interpreter.program_check
rescue Errno::ENOENT, Errno::EISDIR
  console_io.print_line("File '#{filename}' not found")
  false
end

options = {}
OptionParser.new do |opt|
  opt.on('-l', '--list SOURCE') { |o| options[:list_name] = o }
  opt.on('--tokens') { |o| options[:tokens] = o }
  opt.on('-p', '--pretty SOURCE') { |o| options[:pretty_name] = o }
  opt.on('--pretty-multiline') { |o| options[:pretty_multiline] = o }
  opt.on('-r', '--run SOURCE') { |o| options[:run_name] = o }
  opt.on('--profile') { |o| options[:profile] = o }
  opt.on('-c', '--crossref SOURCE') { |o| options[:cref_name] = o }
  opt.on('--parse SOURCE') { |o| options[:parse_name] = o }
  opt.on('--analyze SOURCE') { |o| options[:analyze_name] = o }
  opt.on('--asc-allow-all') { |o| options[:asc_allow_all] = o }
  opt.on('--back-tab') { |o| options[:back_tab] = o }
  opt.on('--base BASE') { |o| options[:base] = o }
  opt.on('--no-cache-const-expr') { |o| options[:no_cache_const_expr] = o }
  opt.on('--chr-allow-all') { |o| options[:chr_allow_all] = o }

  opt.on('--no-detect-infinite-loop') do |o|
    options[:no_detect_infinite_loop] = o
  end

  opt.on('--echo-input') { |o| options[:echo_input] = o }
  opt.on('--no-extend-if') { |o| options[:no_extend_if] = o }
  opt.on('--field-sep-semi') { |o| options[:field_sep_semi] = o }
  opt.on('--forget-fornext') { |o| options[:forget_fornext] = o }
  opt.on('--heading') { |o| options[:heading] = o }
  opt.on('--no-if-for-sub') { |o| options[:no_if_for_sub] = o }
  opt.on('--ignore-randomize') { |o| options[:ignore_randomize] = o }
  opt.on('--ignore-rnd-arg') { |o| options[:ignore_rnd_arg] = o }
  opt.on('--implied-semicolon') { |o| options[:implied_semicolon] = o }
  opt.on('--no-int-bitwise') { |o| options[:no_int_bitwise] = o }
  opt.on('--int-floor') { |o| options[:int_floor] = o }
  opt.on('--lock-fornext') { |o| options[:lock_fornext] = o }
  opt.on('--long-names') { |o| options[:long_names] = o }
  opt.on('--max-dim LIMIT') { |o| options[:max_dim] = o }
  opt.on('--precision DIGITS') { |o| options[:precision] = o }
  opt.on('--print-width WIDTH') { |o| options[:print_width] = o }
  opt.on('--prompt PROMPT') { |o| options[:prompt] = o }
  opt.on('--prompt-count') { |o| options[:prompt_count] = o }
  opt.on('--promptd PROMPT') { |o| options[:promptd] = o }
  opt.on('--provenance') { |o| options[:provenance] = o }
  opt.on('--qmark-after-prompt') { |o| options[:qmark_after_prompt] = o }
  opt.on('--randomize') { |o| options[:randomize] = o }
  opt.on('--relational-boolean') { |o| options[:relational_boolean] = o }
  opt.on('--require-initialized') { |o| options[:require_initialized] = o }

  opt.on('--semicolon-zone-width WIDTH') do |o|
    options[:semicolon_zone_width] = o
  end

  opt.on('--trace') { |o| options[:trace] = o }
  opt.on('--timing') { |o| options[:timing] = o }
  opt.on('--tty') { |o| options[:tty] = o }
  opt.on('--tty-lf') { |o| options[:tty_lf] = o }
  opt.on('--wrap') { |o| options[:wrap] = o }
  opt.on('--zone-width WIDTH') { |o| options[:zone_width] = o }
end.parse!

list_filename = options[:list_name]
list_tokens = options.key?(:tokens)
pretty_filename = options[:pretty_name]
parse_filename = options[:parse_name]
analyze_filename = options[:analyze_name]
run_filename = options[:run_name]
cref_filename = options[:cref_name]
show_profile = options.key?(:profile)

boolean = { type: :bool }
string = { type: :string }
int = { type: :int, min: 0 }
int1to17 = { type: :int, max: 17, min: 1, off: 'INFINITE' }
int132 = { type: :int, max: 132, min: 0 }
int40 = { type: :int, max: 40, min: 0 }
int1 = { type: :int, max: 1, min: 0 }
int32767 = { type: :int, max: 32_767, min: 999 }
separator = { type: :list, values: %w[COMMA SEMI NL NONE] }

all_types = %i[new loaded runtime]
loaded = %i[new loaded]
only_new = %i[new]

$options = {}

$options['apostrophe_comment'] = Option.new(only_new, boolean, true)

$options['asc_allow_all'] =
  Option.new(all_types, boolean, options.key?(:asc_allow_all))

$options['back_tab'] = Option.new(all_types, boolean, options.key?(:back_tab))

base = 0
base = options[:base].to_i if options.key?(:base)
$options['base'] = Option.new(all_types, int1, base)

$options['cache_const_expr'] =
  Option.new(all_types, boolean, !options.key?(:no_cache_const_expr))

$options['chr_allow_all'] =
  Option.new(all_types, boolean, options.key?(:chr_allow_all))

$options['default_prompt'] = Option.new(all_types, string, '? ')

$options['detect_infinite_loop'] =
  Option.new(all_types, boolean, !options.key?(:no_detect_infinite_loop))

$options['echo'] = Option.new(all_types, boolean, options.key?(:echo_input))

$options['extend_if'] =
  Option.new(only_new, boolean, !options.key?(:no_extend_if))

$options['forget_fornext'] =
  Option.new(all_types, boolean, options.key?(:forget_fornext))

$options['heading'] = Option.new(all_types, boolean, options.key?(:heading))

field_sep = Option.new(all_types, separator, 'COMMA')
field_sep = Option.new(all_types, separator, 'SEMI') if
  options.key?(:field_sep_semi)
$options['field_sep'] = field_sep

$options['if_for_sub'] =
  Option.new(only_new, boolean, !options.key?(:no_if_for_sub))

$options['ignore_rnd_arg'] =
  Option.new(all_types, boolean, options.key?(:ignore_rnd_arg))

$options['implied_semicolon'] =
  Option.new(all_types, boolean, options.key?(:implied_semicolon))

$options['int_bitwise'] =
  Option.new(only_new, boolean, !options.key?(:no_int_bitwise))

$options['int_floor'] =
  Option.new(all_types, boolean, options.key?(:int_floor))

$options['lock_fornext'] =
  Option.new(all_types, boolean, options.key?(:lock_fornext))

long_names = options.key?(:long_names)
$options['long_names'] = Option.new(only_new, boolean, long_names)

max_dim = 255
max_dim = options[:max_dim].to_i if options.key?(:max_dim)
$options['max_dim'] = Option.new(all_types, int, max_dim)

$options['max_line_num'] = Option.new(only_new, int32767, 32_767)
$options['min_line_num'] = Option.new(only_new, int1, 1)

newline_speed = 0
newline_speed = 10 if options.key?(:tty_lf)
$options['newline_speed'] = Option.new(all_types, int, newline_speed)

precision = 9
if options.key?(:precision)
  precision = options[:precision]
  precision = precision.to_i if precision =~ /\A\d+\z/
end
$options['precision'] = Option.new(all_types, int1to17, precision)

$options['pretty_multiline'] =
  Option.new(loaded, boolean, options.key?(:pretty_multiline))

print_speed = 0
print_speed = 10 if options.key?(:tty)
$options['print_speed'] = Option.new(all_types, int, print_speed)

print_width = 72
print_width = options[:print_width].to_i if options.key?(:print_width)
$options['print_width'] = Option.new(all_types, int132, print_width)

$options['prompt'] = Option.new(loaded, string, 'READY')
if options.key?(:prompt)
  prompt = options[:prompt]
  $options['prompt'] = Option.new(loaded, string, prompt)
end

$options['promptd'] = Option.new(loaded, string, 'DEBUG')
if options.key?(:promptd)
  promptd = options[:promptd]
  $options['promptd'] = Option.new(loaded, string, promptd)
end

$options['prompt_count'] =
  Option.new(all_types, boolean, options.key?(:prompt_count))

$options['provenance'] =
  Option.new(all_types, boolean, options.key?(:provenance))

$options['qmark_after_prompt'] =
  Option.new(all_types, boolean, options.key?(:qmark_after_prompt))

$options['randomize'] =
  Option.new(all_types, boolean, options.key?(:randomize))

$options['relational_boolean'] =
  Option.new(only_new, boolean, options.key?(:relational_boolean))

$options['require_initialized'] =
  Option.new(all_types, boolean, options.key?(:require_initialized))

$options['respect_randomize'] =
  Option.new(all_types, boolean, !options.key?(:ignore_randomize))

semicolon_zone_width = 0
if options.key?(:semicolon_zone_width)
  semicolon_zone_width = options[:semicolon_zone_width].to_i
end

$options['semicolon_zone_width'] =
  Option.new(all_types, int, semicolon_zone_width)

$options['timing'] = Option.new(all_types, boolean, options.key?(:timing))
$options['trace'] = Option.new(all_types, boolean, options.key?(:trace))
$options['wrap'] = Option.new(all_types, boolean, options.key?(:wrap))

zone_width = 16
zone_width = options[:zone_width].to_i if options.key?(:zone_width)
$options['zone_width'] = Option.new(all_types, int40, zone_width)

statement_seps = [':', '\\']

quotes = ['"']

comment_leads = []
comment_leads << "'" if $options['apostrophe_comment'].value

console_io = ConsoleIo.new

tokenbuilders =
  make_interpreter_tokenbuilders($options, quotes, statement_seps,
                                 comment_leads)

interpreter = Interpreter.new(console_io)
interpreter.set_default_args('RND', NumericConstant.new(1))
interpreter.set_default_args('RND%', IntegerConstant.new(100))
interpreter.set_default_args('RND$', NumericConstant.new(6))
program = Program.new(console_io, tokenbuilders)
interpreter.program = program

if $options['heading'].value
  console_io.print_line('BASIC-1978 interpreter version -1')
  console_io.newline
end

# list the source
unless list_filename.nil?
  args = [TextConstant.new(list_filename)]

  filename, _keywords = parse_args(args)

  if load_file_command_line(filename, interpreter, console_io)
    texts = interpreter.program_list('', list_tokens)
    texts.each { |text| console_io.print_line(text) }
  else
    interpreter.print_program_errors
  end

  console_io.newline
end

# show parse dump
unless parse_filename.nil?
  args = [TextConstant.new(parse_filename)]

  filename, _keywords = parse_args(args)

  if load_file_command_line(filename, interpreter, console_io)
    texts = interpreter.program_parse('')
    texts.each { |text| console_io.print_line(text) }
  else
    interpreter.print_program_errors
  end

  console_io.newline
end

# show analysis
unless analyze_filename.nil?
  args = [TextConstant.new(analyze_filename)]

  filename, _keywords = parse_args(args)

  if load_file_command_line(filename, interpreter, console_io) &&
     interpreter.program_okay?
    texts = interpreter.program_analyze
    texts.each { |text| console_io.print_line(text) }
  else
    interpreter.print_program_errors
  end
end

# pretty-print the source
unless pretty_filename.nil?
  args = [TextConstant.new(pretty_filename)]

  filename, _keywords = parse_args(args)

  if load_file_command_line(filename, interpreter, console_io)
    pretty_multiline = $options['pretty_multiline'].value
    texts = interpreter.program_pretty('', pretty_multiline)
    texts.each { |text| console_io.print_line(text) }
  else
    interpreter.print_program_errors
  end

  console_io.newline
end

# cross-reference the source
unless cref_filename.nil?
  args = [TextConstant.new(cref_filename)]

  filename, _keywords = parse_args(args)

  if load_file_command_line(filename, interpreter, console_io)
    texts = interpreter.program_crossref
    texts.each { |text| console_io.print_line(text) }
  else
    interpreter.print_program_errors
  end
end

# run the source
unless run_filename.nil?
  args = [TextConstant.new(run_filename)]

  filename, _keywords = parse_args(args)

  if load_file_command_line(filename, interpreter, console_io) &&
     interpreter.program_okay?
    begin
      timing = Benchmark.measure do
        interpreter.run
        console_io.newline
      end

      show_timing = $options['timing'].value
      if show_timing
        print_timing(timing, console_io)
        console_io.newline
      end

      if show_profile
        texts = interpreter.program_profile('', show_timing)
        texts.each { |text| console_io.print_line(text) }
        console_io.newline
      end
    rescue BASICCommandError => e
      console_io.print_line(e.to_s)
    end
  else
    interpreter.print_program_errors
  end
end

# no command-line directives, so run BASIC shell
if list_filename.nil? && parse_filename.nil? && analyze_filename.nil? &&
   pretty_filename.nil? && cref_filename.nil? && run_filename.nil?

  tokenbuilders = make_command_tokenbuilders(quotes, long_names)

  shell = Shell.new(console_io, interpreter, tokenbuilders)
  shell.run
end

if $options['heading'].value
  console_io.newline
  console_io.print_line('BASIC-1978 ended')
end
