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
  attr_reader :value

  def initialize(defs, value)
    @defs = defs
    check_value(value)
    @value = value
  end

  def set(value)
    check_value(value)
    @value = value
  end

  def to_s
    case @defs[:type]
    when :bool
      @value.to_s
    when :int
      @value.to_s
    when :float
      @value.to_s
    when :string
      '"' + @value.to_s + '"'
    end
  end

  private

  def check_value(value)
    type = @defs[:type]
    case type
    when :bool
      legals = %w(TrueClass FalseClass)

      raise(BASICRuntimeError, "Invalid type #{value.class} for boolean") unless
        legals.include?(value.class.to_s)
    when :int
      legals = %w(Fixnum Integer)

      raise(BASICRuntimeError, "Invalid type #{value.class} for integer") unless
        legals.include?(value.class.to_s)

      min = @defs[:min]
      if !min.nil? && value < min
        raise(BASICRuntimeError, "Value #{value} below minimum #{min}")
      end

      max = @defs[:max]
      if !max.nil? && value > max
        raise(BASICRuntimeError, "Value #{value} above maximum #{max}")
      end
    when :float
      legals = %w(Fixnum Integer Float Rational)

      raise(BASICRuntimeError, "Invalid type #{value.class} for float") unless
        legals.include?(value.class.to_s)

      min = @defs[:min]
      if !min.nil? && value < min
        raise(BASICRuntimeError, "Value #{value} below minimum #{min}")
      end

      max = @defs[:max]
      if !max.nil? && value > max
        raise(BASICRuntimeError, "Value #{value} above maximum #{max}")
      end
    when :string
      legals = %(String)

      raise(BASICRuntimeError, "Invalid type #{value.class} for string") unless
        legals.include?(value.class.to_s)
    else
      raise(BASICRuntimeError, 'Unknown value type')
    end
  end
end

# interactive shell
class Shell
  def initialize(console_io, interpreter, program, tokenbuilders)

    @console_io = console_io
    @interpreter = interpreter
    @program = program
    @tokenbuilders = tokenbuilders
    @invalid_tokenbuilder = InvalidTokenBuilder.new
  end

  def run
    need_prompt = true
    @done = false

    until @done
      @console_io.print_line('READY') if need_prompt
      cmd = @console_io.read_line
      need_prompt = process_line(cmd)
    end
  end

  private

  def process_line(line)
    # starts with a number, so maybe it is a program line
    return @program.store_program_line(line, true) if /\A\d/ =~ line

    # immediate command -- tokenize and execute
    tokenizer = Tokenizer.new(@tokenbuilders, @invalid_tokenbuilder)
    tokens = tokenizer.tokenize(line)
    tokens.delete_if(&:whitespace?)

    process_command(tokens, line)
  end

  def process_command(tokens, line)
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

  def option_command(args)
    if args.empty?
      $options.each do |option|
        name = option[0].upcase
        value = option[1].value.to_s.upcase
        @console_io.print_line(name + ' ' + value)
      end
    elsif args.size == 1 && args[0].keyword?
      kwd = args[0].to_s
      kwd_d = kwd.downcase

      if $options.key?(kwd_d)
        value = $options[kwd_d].value.to_s.upcase
        @console_io.print_line("#{kwd} #{value}")
      else
        @console_io.print_line("Unknown option #{kwd}")
        @console_io.newline
      end
    elsif args.size == 2 && args[0].keyword?
      kwd = args[0].to_s
      kwd_d = kwd.downcase

      if $options.key?(kwd_d)
        begin
          if args[1].boolean_constant?
            boolean = BooleanConstant.new(args[1])
            $options[kwd_d].set(boolean.to_v)
          else
            @console_io.print_line('Incorrect value type')
          end
        rescue BASICRuntimeError => e
          @console_io.print_line(e.to_s)
        end
        value = $options[kwd_d].value.to_s.upcase
        @console_io.print_line("#{kwd} #{value}")
      else
        @console_io.print_line("Unknown option #{kwd}")
        @console_io.newline
      end
    else
      @console_io.print_line('Syntax error')
      @console_io.newline
    end
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
      @program.cmd_new
      @interpreter.clear_variables
      @interpreter.clear_breakpoints
    when 'RUN'
      if @program.check
        # duplicate the options
        options_2 = {}
        $options.each { |name, option| options_2[name] = duplicate(option) }

        timing = Benchmark.measure {
          @program.run(@interpreter)
        }
        # restore options to undo any changes during the run
        options_2.each { |name, option| $options[name] = option }

        # print timing info
        print_timing(timing, @console_io) if $options['timing'].value
      end
    when 'BREAK'
      @interpreter.set_breakpoints(args)
    when 'LOAD'
      @interpreter.clear_breakpoints
      @program.load(args)
    when 'SAVE'
      @program.save(args)
    when 'LIST'
      @program.list(args, false)
    when 'PRETTY'
      pretty_multiline = $options['pretty_multiline'].value
      @program.pretty(args, pretty_multiline)
    when 'DELETE'
      @program.delete(args)
    when 'PROFILE'
      @program.profile(args)
    when 'RENUMBER'
      if @program.check
        renumber_map = @program.renumber
        @interpreter.renumber_breakpoints(renumber_map)
      end
    when 'CROSSREF'
      @program.crossref if @program.check
    when 'DIMS'
      @interpreter.dump_dims
    when 'PARSE'
      @program.parse(args)
    when 'TOKENS'
      @program.list(args, true)
    when 'UDFS'
      @interpreter.dump_user_functions
    when 'VARS'
      @interpreter.dump_vars
    when 'OPTION'
      option_command(args)
    else
      @console_io.print_line("Unknown command #{keyword}")
      @console_io.newline
    end

    need_prompt
  rescue BASICCommandError => e
    @console_io.print_line(e.to_s)
    @console_io.newline
    true
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

  tokenbuilders << ListTokenBuilder.new(['(', '['], GroupStartToken)
  tokenbuilders << ListTokenBuilder.new([')', ']'], GroupEndToken)
  tokenbuilders << ListTokenBuilder.new([',', ';'], ParamSeparatorToken)

  tokenbuilders <<
    ListTokenBuilder.new(FunctionFactory.function_names, FunctionToken)

  tokenbuilders <<
    ListTokenBuilder.new(FunctionFactory.user_function_names, UserFunctionToken)

  tokenbuilders << TextTokenBuilder.new(quotes)
  tokenbuilders << NumberTokenBuilder.new
  tokenbuilders << IntegerTokenBuilder.new

  long_names = options['long_names'].value
  tokenbuilders << VariableTokenBuilder.new(long_names)
  tokenbuilders << ListTokenBuilder.new(%w(TRUE FALSE), BooleanConstantToken)
  tokenbuilders << WhitespaceTokenBuilder.new
end

def make_command_tokenbuilders(options, quotes)
  tokenbuilders = []

  keywords = %w(
    BREAK CROSSREF DELETE DIMS EXIT LIST LOAD NEW OPTION PARSE PRETTY
    PROFILE RENUMBER RUN SAVE TOKENS UDFS VARS
    APOSTROPHE_COMMENT ASC_ALLOW_ALL
    BACK_TAB
    BASE
    CHR_ALLOW_ALL
    DECIMALS DEFAULT_PROMPT DETECT_INFINITE_LOOP
    ECHO EPSILON HEADING
    IF_FALSE_NEXT_LINE IGNORE_RND_ARG IMPLIED_SEMICOLON
    INT_FLOOR LOCK_FORNEXT LONG_NAMES NEWLINE_SPEED
    PRETTY_MULTILINE PRINT_SPEED PRINT_WIDTH PROMPT_COUNT PROVENANCE
    QMARK_AFTER_PROMPT RANDOMIZE REQUIRE_INITIALIZED RESPECT_RANDOMIZE
    SEMICOLON_ZONE_WIDTH TIMING TRACE ZONE_WIDTH
  )
  tokenbuilders << ListTokenBuilder.new(keywords, KeywordToken)

  un_ops = UnaryOperator.operators
  bi_ops = BinaryOperator.operators
  operators = (un_ops + bi_ops).uniq
  tokenbuilders << ListTokenBuilder.new(operators, OperatorToken)

  tokenbuilders << ListTokenBuilder.new([',', ';'], ParamSeparatorToken)

  tokenbuilders << TextTokenBuilder.new(quotes)

  tokenbuilders << NumberTokenBuilder.new

  tokenbuilders << ListTokenBuilder.new(%w(TRUE FALSE), BooleanConstantToken)
  tokenbuilders << WhitespaceTokenBuilder.new
end

def print_timing(timing, console_io)
  user_time = timing.utime + timing.cutime
  sys_time = timing.stime + timing.cstime
  console_io.newline
  console_io.print_line('CPU time:')
  console_io.print_line(" user: #{user_time.round(2)}")
  console_io.print_line(" system: #{sys_time.round(2)}")
  console_io.newline
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
  opt.on('--asc-allow-all') { |o| options[:asc_allow_all] = o }
  opt.on('--back-tab') { |o| options[:back_tab] = o }
  opt.on('--base BASE') { |o| options[:base] = o }
  opt.on('--chr-allow-all') { |o| options[:chr_allow_all] = o }
  opt.on('--decimals DIGITS') { |o| options[:decimals] = o }
  opt.on('--no-detect-infinite-loop') { |o| options[:no_detect_infinite_loop] = o }
  opt.on('--echo-input') { |o| options[:echo_input] = o }
  opt.on('--epsilon LIMIT') { |o| options[:epsilon] = o }
  opt.on('--heading') { |o| options[:heading] = o }
  opt.on('--if-false-next-line') { |o| options[:if_false_next_line] = o }
  opt.on('--ignore-randomize') { |o| options[:ignore_randomize] = o }
  opt.on('--ignore-rnd-arg') { |o| options[:ignore_rnd_arg] = o }
  opt.on('--implied-semicolon') { |o| options[:implied_semicolon] = o }
  opt.on('--int-floor') { |o| options[:int_floor] = o }
  opt.on('--lock-fornext') { |o| options[:lock_fornext] = o }
  opt.on('--long-names') { |o| options[:long_names] = o }
  opt.on('--print-width WIDTH') { |o| options[:print_width] = o }
  opt.on('--prompt-count') { |o| options[:prompt_count] = o }
  opt.on('--provenance') { |o| options[:provenance] = o }
  opt.on('--qmark-after-prompt') { |o| options[:qmark_after_prompt] = o }
  opt.on('--randomize') { |o| options[:randomize] = o }
  opt.on('--require-initialized') { |o| options[:require_initialized] = o }
  opt.on('--semicolon-zone-width WIDTH') { |o| options[:semicolon_zone_width] = o }
  opt.on('--trace') { |o| options[:trace] = o }
  opt.on('--timing') { |o| options[:timing] = o }
  opt.on('--tty') { |o| options[:tty] = o }
  opt.on('--tty-lf') { |o| options[:tty_lf] = o }
  opt.on('--zone-width WIDTH') { |o| options[:zone_width] = o }
end.parse!

list_filename = options[:list_name]
list_tokens = options.key?(:tokens)
pretty_filename = options[:pretty_name]
parse_filename = options[:parse_name]
run_filename = options[:run_name]
cref_filename = options[:cref_name]
show_profile = options.key?(:profile)

boolean = { :type => :bool }
string = { :type => :string }
int = { :type => :int, :min => 0 }
int_1_15 = { :type => :int, :max => 15, :min => 1 }
int_132 = { :type => :int, :max => 132, :min => 0 }
int_40 = { :type => :int, :max => 40, :min => 0 }
int_1 = { :type => :int, :max => 1, :min => 0 }
float = { :type => :float, :min => 0 }

$options = {}

$options['apostrophe_comment'] = Option.new(boolean, true)

$options['asc_allow_all'] =
  Option.new(boolean, options.key?(:asc_allow_all))

$options['back_tab'] = Option.new(boolean, options.key?(:back_tab))

base = 0
base = options[:base].to_i if options.key?(:base)
$options['base'] = Option.new(int_1, base)

$options['chr_allow_all'] =
  Option.new(boolean, options.key?(:chr_allow_all))

decimals = 5
decimals = options[:decimals] if options.key?(:decimals)
$options['decimals'] = Option.new(int_1_15, decimals)

$options['default_prompt'] = Option.new(string, '? ')

$options['detect_infinite_loop'] =
  Option.new(boolean, !options.key?(:no_detect_infinite_loop))

$options['echo'] = Option.new(boolean, options.key?(:echo_input))

epsilon = 1e-7
epsilon = options[:epsilon].to_f if options.key?(:epsilon)
$options['epsilon'] = Option.new(float, epsilon)

$options['heading'] = Option.new(boolean, options.key?(:heading))

$options['if_false_next_line'] =
  Option.new(boolean, options.key?(:if_false_next_line))

$options['ignore_rnd_arg'] =
  Option.new(boolean, options.key?(:ignore_rnd_arg))

$options['implied_semicolon'] =
  Option.new(boolean, options.key?(:implied_semicolon))

$options['int_floor'] = Option.new(boolean, options.key?(:int_floor))

$options['lock_fornext'] =
  Option.new(boolean, options.key?(:lock_fornext))

$options['long_names'] = Option.new(boolean, options.key?(:long_names))

newline_speed = 0
newline_speed = 10 if options.key?(:tty_lf)
$options['newline_speed'] = Option.new(int, newline_speed)

$options['pretty_multiline'] =
  Option.new(boolean, options.key?(:pretty_multiline))

print_speed = 0
print_speed = 10 if options.key?(:tty)
$options['print_speed'] = Option.new(int, print_speed)

print_width = 72
print_width = options[:print_width].to_i if options.key?(:print_width)
$options['print_width'] = Option.new(int_132, print_width)

$options['prompt_count'] = Option.new(boolean, options.key?(:prompt_count))

$options['provenance'] = Option.new(boolean, options.key?(:provenance))

$options['qmark_after_prompt'] =
  Option.new(boolean, options.key?(:qmark_after_prompt))

$options['randomize'] = Option.new(boolean, options.key?(:randomize))

$options['require_initialized'] =
  Option.new(boolean, options.key?(:require_initialized))

$options['respect_randomize'] =
  Option.new(boolean, !options.key?(:ignore_randomize))

semicolon_zone_width = 0
if options.key?(:semicolon_zone_width)
  semicolon_zone_width = options[:semicolon_zone_width].to_i
end

$options['semicolon_zone_width'] = Option.new(int, semicolon_zone_width)

$options['timing'] = Option.new(boolean, options.key?(:timing))
$options['trace'] = Option.new(boolean, options.key?(:trace))

zone_width = 16
zone_width = options[:zone_width].to_i if options.key?(:zone_width)
$options['zone_width'] = Option.new(int_40, zone_width)

statement_seps = [':', '\\']

quotes = ['"']

comment_leads = []
comment_leads << "'" if $options['apostrophe_comment'].value

console_io = ConsoleIo.new

tokenbuilders =
  make_interpreter_tokenbuilders($options, quotes, statement_seps,
                                 comment_leads)

if $options['heading'].value
  console_io.print_line('BASIC-1978 interpreter version -1')
  console_io.newline
end

program = Program.new(console_io, tokenbuilders)

if !run_filename.nil?
  token = TextConstantToken.new('"' + run_filename + '"')
  nametokens = [TextConstant.new(token)]
  if program.load(nametokens) && program.check
    interpreter = Interpreter.new(console_io)
    interpreter.set_default_args('RND', NumericConstant.new(1))

    timing = Benchmark.measure {
      program.run(interpreter)
    }

    print_timing(timing, console_io) if $options['timing'].value
    program.profile('') if show_profile
  end
elsif !list_filename.nil?
  token = TextConstantToken.new('"' + list_filename + '"')
  nametokens = [TextConstant.new(token)]
  if program.load(nametokens)
    program.list('', list_tokens)
  end
elsif !parse_filename.nil?
  token = TextConstantToken.new('"' + parse_filename + '"')
  nametokens = [TextConstant.new(token)]
  if program.load(nametokens)
    program.parse('')
  end
elsif !pretty_filename.nil?
  token = TextConstantToken.new('"' + pretty_filename + '"')
  nametokens = [TextConstant.new(token)]
  if program.load(nametokens)
    pretty_multiline = $options['pretty_multiline'].value
    program.pretty('', pretty_multiline)
  end
elsif !cref_filename.nil?
  token = TextConstantToken.new('"' + cref_filename + '"')
  nametokens = [TextConstant.new(token)]
  if program.load(nametokens)
    program.crossref
  end
else
  interpreter = Interpreter.new(console_io)
  interpreter.set_default_args('RND', NumericConstant.new(1))

  tokenbuilders = make_command_tokenbuilders($options, quotes)

  shell = Shell.new(console_io, interpreter, program, tokenbuilders)

  shell.run
end

if $options['heading'].value
  console_io.newline
  console_io.print_line('BASIC-1978 ended')
end
