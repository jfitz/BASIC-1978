#!/usr/bin/ruby

require 'benchmark'
require 'optparse'
require 'singleton'
require 'io/console'

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

  private

  def check_value(value)
    type = @defs[:type]
    case type
    when :bool
      legals = %w(TrueClass FalseClass)

      raise(BASICRuntimeError, 'Invalid value') unless
        legals.include?(value.class.to_s)
    when :int
      legals = %w(Fixnum)

      raise(BASICRuntimeError, 'Invalid value') unless
        legals.include?(value.class.to_s)

      min = @defs[:min]
      if !min.nil? && value < min
        raise(BASICRuntimeError, 'Valid below minimum')
      end

      max = @defs[:max]
      if !max.nil? && value > max
        raise(BASICRuntimeError, 'Valid above maximum')
      end
    when :string
      legals = %(String)

      raise(BASICRuntimeError, 'Invalid value') unless
        legals.include?(value.class.to_s)
    else
      raise(BASICRuntimeError, 'Unknown value type')
    end
  end
end

# interactive shell
class Shell
  def initialize(console_io, interpreter, program, action_options,
                 tokenbuilders)

    @console_io = console_io
    @interpreter = interpreter
    @program = program
    @action_options = action_options
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
      @action_options.each do |option|
        name = option[0].upcase
        value = option[1].value.to_s.upcase
        @console_io.print_line(name + ' ' + value)
      end
    elsif args.size == 1 && args[0].keyword?
      kwd = args[0].to_s
      kwd_d = kwd.downcase

      if @action_options.key?(kwd_d)
        value = @action_options[kwd_d].value.to_s.upcase
        @console_io.print_line("#{kwd} #{value}")
      else
        @console_io.print_line("Unknown option #{kwd}")
        @console_io.newline
      end
    elsif args.size == 2 && args[0].keyword?
      kwd = args[0].to_s
      kwd_d = kwd.downcase

      if @action_options.key?(kwd_d)
        begin
          if args[1].boolean_constant?
            boolean = BooleanConstant.new(args[1])
            @action_options[kwd_d].set(boolean.to_v)
          else
            @console_io.print_line('Incorrect value type')
          end
        rescue BASICRuntimeError => e
          @console_io.print_line(e)
        end
        value = @action_options[kwd_d].value.to_s.upcase
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
        timing = Benchmark.measure {
          @program.run(@interpreter, @action_options)
        }
        print_timing(timing, @console_io) if @action_options['timing'].value
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
      pretty_multiline = @action_options['pretty_multiline'].value
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

def make_interpreter_tokenbuilders(token_options, quotes, statement_separators,
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

  colon_file = token_options['colon_file'].value
  un_ops = UnaryOperator.operators(colon_file)
  min_max_op = token_options['min_max_op'].value
  bi_ops = BinaryOperator.operators(min_max_op)
  operators = (un_ops + bi_ops).uniq
  tokenbuilders << ListTokenBuilder.new(operators, OperatorToken)

  tokenbuilders << BreakTokenBuilder.new

  tokenbuilders << ListTokenBuilder.new(['(', '['], GroupStartToken)
  tokenbuilders << ListTokenBuilder.new([')', ']'], GroupEndToken)
  tokenbuilders << ListTokenBuilder.new([',', ';'], ParamSeparatorToken)

  tokenbuilders <<
    ListTokenBuilder.new(FunctionFactory.function_names, FunctionToken)

  tokenbuilders <<
    ListTokenBuilder.new(FunctionFactory.user_function_names, UserFunctionToken)

  tokenbuilders << TextTokenBuilder.new(quotes)
  allow_hash_constant = token_options['allow_hash_constant'].value
  tokenbuilders << NumberTokenBuilder.new(allow_hash_constant)
  tokenbuilders << IntegerTokenBuilder.new
  allow_pi = token_options['allow_pi'].value
  tokenbuilders << NumericSymbolTokenBuilder.new if allow_pi
  allow_ascii = token_options['allow_ascii'].value
  tokenbuilders << TextSymbolTokenBuilder.new if allow_ascii
  tokenbuilders << VariableTokenBuilder.new

  tokenbuilders <<
    ListTokenBuilder.new(%w(TRUE FALSE), BooleanConstantToken)

  tokenbuilders << WhitespaceTokenBuilder.new
end

def make_command_tokenbuilders(token_options, quotes)
  tokenbuilders = []

  keywords = %w(
    BASE BREAK CROSSREF DELETE DIMS EXIT HEADING LIST LOAD NEW OPTION PARSE
    PRETTY PRETTY_MULTILINE PROFILE PROVENENCE RENUMBER RUN SAVE TIMING
    TOKENS TRACE UDFS VARS
  )
  tokenbuilders << ListTokenBuilder.new(keywords, KeywordToken)

  colon_file = token_options['colon_file'].value
  un_ops = UnaryOperator.operators(colon_file)
  min_max_op = token_options['min_max_op'].value
  bi_ops = BinaryOperator.operators(min_max_op)
  operators = (un_ops + bi_ops).uniq
  tokenbuilders << ListTokenBuilder.new(operators, OperatorToken)

  tokenbuilders << ListTokenBuilder.new([',', ';'], ParamSeparatorToken)

  tokenbuilders << TextTokenBuilder.new(quotes)

  allow_hash_constant = token_options['allow_hash_constant'].value
  tokenbuilders << NumberTokenBuilder.new(allow_hash_constant)

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
  opt.on('--no-heading') { |o| options[:no_heading] = o }
  opt.on('--echo-input') { |o| options[:echo_input] = o }
  opt.on('--trace') { |o| options[:trace] = o }
  opt.on('--provenence') { |o| options[:provenence] = o }
  opt.on('--no-timing') { |o| options[:no_timing] = o }
  opt.on('--tty') { |o| options[:tty] = o }
  opt.on('--tty-lf') { |o| options[:tty_lf] = o }
  opt.on('--input-high-bit') { |o| options[:input_high_bit] = o }
  opt.on('--no-colon-separator') { |o| options[:no_colon_sep] = o }
  opt.on('--colon-file') { |o| options[:colon_file] = o }
  opt.on('--bang-comment') { |o| options[:bang_comment] = o }
  opt.on('--print-width WIDTH') { |o| options[:print_width] = o }
  opt.on('--zone-width WIDTH') { |o| options[:zone_width] = o }
  opt.on('--back-tab') { |o| options[:back_tab] = o }
  opt.on('--int-floor') { |o| options[:int_floor] = o }
  opt.on('--ignore-rnd-arg') { |o| options[:ignore_rnd_arg] = o }
  opt.on('--implied-semicolon') { |o| options[:implied_semicolon] = o }
  opt.on('--qmark-after-prompt') { |o| options[:qmark_after_prompt] = o }
  opt.on('--randomize') { |o| options[:randomize] = o }
  opt.on('--ignore-randomize') { |o| options[:ignore_randomize] = o }
  opt.on('--if-false-next-line') { |o| options[:if_false_next_line] = o }
  opt.on('--fornext-one-beyond') { |o| options[:fornext_one_beyond] = o }
  opt.on('--lock-fornext') { |o| options[:lock_fornext] = o }
  opt.on('--base BASE') { |o| options[:base] = o }
  opt.on('--require-initialized') { |o| options[:require_initialized] = o }
  opt.on('--hash-constant') { |o| options[:hash_constant] = o }
  opt.on('--define-pi') { |o| options[:allow_pi] = o }
  opt.on('--define-ascii') { |o| options[:allow_ascii] = o }
  opt.on('--min-max-op') { |o| options[:min_max_op] = o }
  opt.on('--asc-allow-all') { |o| options[:asc_allow_all] = o }
  opt.on('--chr-allow-all') { |o| options[:chr_allow_all] = o }
  opt.on('--single-quote-strings') { |o| options[:single_quote_strings] = o }
  opt.on('--crlf-on-line-input') { |o| options[:crlf_on_line_input] = o }
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
int_132 = { :type => :int, :max => 132, :min => 0 }
int_40 = { :type => :int, :max => 40, :min => 0 }
int_1 = { :type => :int, :max => 1, :min => 0 }

action_options = {}

base = 0
base = options[:base].to_i if options.key?(:base)
action_options['base'] = Option.new(int_1, base)

action_options['heading'] = Option.new(boolean, !options.key?(:no_heading))

action_options['pretty_multiline'] =
  Option.new(boolean, options.key?(:pretty_multiline))

action_options['provenence'] = Option.new(boolean, options.key?(:provenence))
action_options['timing'] = Option.new(boolean, !options.key?(:no_timing))
action_options['trace'] = Option.new(boolean, options.key?(:trace))

output_options = {}

output_options['back_tab'] = Option.new(boolean, options.key?(:back_tab))

output_options['crlf_on_line_input'] =
  Option.new(boolean, options.key?(:crlf_on_line_input))

output_options['default_prompt'] = Option.new(string, '? ')

output_options['echo'] = Option.new(boolean, options.key?(:echo_input))

output_options['implied_semicolon'] =
  Option.new(boolean, options.key?(:implied_semicolon))

output_options['input_high_bit'] =
  Option.new(boolean, options.key?(:input_high_bit))

newline_speed = 0
newline_speed = 10 if options.key?(:tty_lf)
output_options['newline_speed'] = Option.new(int, newline_speed)

print_width = 72
print_width = options[:print_width].to_i if options.key?(:print_width)
output_options['print_width'] = Option.new(int_132, print_width)

output_options['qmark_after_prompt'] =
  Option.new(boolean, options.key?(:qmark_after_prompt))

print_speed = 0
print_speed = 10 if options.key?(:tty)
output_options['print_speed'] = Option.new(int, print_speed)

zone_width = 16
zone_width = options[:zone_width].to_i if options.key?(:zone_width)
output_options['zone_width'] = Option.new(int_40, zone_width)

interpreter_options = {}

interpreter_options['asc_allow_all'] =
  Option.new(boolean, options.key?(:asc_allow_all))

interpreter_options['chr_allow_all'] =
  Option.new(boolean, options.key?(:chr_allow_all))

interpreter_options['fornext_one_beyond'] =
  Option.new(boolean, options.key?(:fornext_one_beyond))

interpreter_options['if_false_next_line'] =
  Option.new(boolean, options.key?(:if_false_next_line))

interpreter_options['ignore_rnd_arg'] =
  Option.new(boolean, options.key?(:ignore_rnd_arg))

interpreter_options['int_floor'] = Option.new(boolean, options.key?(:int_floor))

interpreter_options['lock_fornext'] =
  Option.new(boolean, options.key?(:lock_fornext))

interpreter_options['randomize'] = Option.new(boolean, options.key?(:randomize))

interpreter_options['require_initialized'] =
  Option.new(boolean, options.key?(:require_initialized))

interpreter_options['respect_randomize'] =
  Option.new(boolean, !options.key?(:ignore_randomize))

token_options = {}
token_options['allow_ascii'] = Option.new(boolean, options.key?(:allow_ascii))

token_options['allow_hash_constant'] =
  Option.new(boolean, options.key?(:hash_constant))

token_options['allow_pi'] = Option.new(boolean, options.key?(:allow_pi))
token_options['apostrophe_comment'] = Option.new(boolean, true)
token_options['backslash_separator'] = Option.new(boolean, true)
token_options['bang_comment'] = Option.new(boolean, options.key?(:bang_comment))
token_options['colon_file'] = Option.new(boolean, options.key?(:colon_file))

colon_separator = !options.key?(:no_colon_sep) && !options.key?(:colon_file)
token_options['colon_separator'] = Option.new(boolean, colon_separator)

token_options['min_max_op'] = Option.new(boolean, options.key?(:min_max_op))

token_options['single_quote_strings'] =
  Option.new(boolean, options.key?(:single_quote_strings))

statement_seps = []
statement_seps << '\\' if token_options['backslash_separator'].value
statement_seps << ':' if token_options['colon_separator'].value
quotes = []
quotes << '"'
quotes << "'" if token_options['single_quote_strings'].value
comment_leads = []
comment_leads << '!' if token_options['bang_comment'].value

comment_leads << "'" if
  token_options['apostrophe_comment'].value &&
  !token_options['single_quote_strings'].value

console_io = ConsoleIo.new(output_options)

tokenbuilders =
  make_interpreter_tokenbuilders(token_options, quotes, statement_seps,
                                 comment_leads)

if action_options['heading'].value
  console_io.print_line('BASIC-1973 interpreter version -1')
  console_io.newline
end

program = Program.new(console_io, tokenbuilders)

if !run_filename.nil?
  token = TextConstantToken.new('"' + run_filename + '"')
  nametokens = [TextConstant.new(token)]
  if program.load(nametokens) && program.check
    interpreter = Interpreter.new(console_io, interpreter_options)
    interpreter.set_default_args('RND', NumericConstant.new(1))

    timing = Benchmark.measure {
      program.run(interpreter, action_options)
    }

    print_timing(timing, console_io) if action_options['timing'].value
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
    pretty_multiline = action_options['pretty_multiline'].value
    program.pretty('', pretty_multiline)
  end
elsif !cref_filename.nil?
  token = TextConstantToken.new('"' + cref_filename + '"')
  nametokens = [TextConstant.new(token)]
  if program.load(nametokens)
    program.crossref
  end
else
  interpreter = Interpreter.new(console_io, interpreter_options)
  interpreter.set_default_args('RND', NumericConstant.new(1))

  tokenbuilders = make_command_tokenbuilders(token_options, quotes)

  shell =
    Shell.new(console_io, interpreter, program, action_options,
              tokenbuilders)

  shell.run
end

if action_options['heading'].value
  console_io.newline
  console_io.print_line('BASIC-1973 ended')
end
