# Helper class for FOR/NEXT
class AbstractForControl
  attr_reader :control
  attr_reader :start
  attr_accessor :start_line_stmt_mod
  attr_accessor :forget

  def initialize(control, start, step, start_line_stmt_mod)
    @control = control
    @start = start
    @step = step
    @start_line_stmt_mod = start_line_stmt_mod
    @forget = false
  end

  def bump_early?
    true
  end

  def bump_control(interpreter)
    current_value = interpreter.get_value(@control)
    current_value += @step

    interpreter.unlock_variable(@control) if $options['lock_fornext'].value
    interpreter.set_value(@control, current_value)
    interpreter.lock_variable(@control) if $options['lock_fornext'].value
  end
end

# Helper class for FOR-TO/NEXT
class ForToControl < AbstractForControl
  attr_reader :end

  def initialize(control, start, step, endv, start_line_stmt_mod)
    super(control, start, step, start_line_stmt_mod)

    @end = endv
  end

  def bump_early?
    false
  end

  def front_terminated?(_)
    zero = NumericConstant.new(0)

    if @step > zero
      @start > @end
    elsif @step < zero
      @start < @end
    else
      false
    end
  end

  def terminated?(interpreter)
    zero = NumericConstant.new(0)
    current_value = interpreter.get_value(@control)

    if @step > zero
      current_value + @step > @end
    elsif @step < zero
      current_value + @step < @end
    else
      false
    end
  end
end

# Helper class for FOR-UNTIL/NEXT
class ForUntilControl < AbstractForControl
  attr_reader :end

  def initialize(control, start, step, expression, start_line_stmt_mod)
    super(control, start, step, start_line_stmt_mod)

    @expression = expression
  end

  def front_terminated?(interpreter)
    values = @expression.evaluate(interpreter)

    raise(BASICExpressionError, 'Expression error') unless values.size == 1

    result = values[0]
    result = BooleanConstant.new(result.to_b) unless result.boolean_constant?

    result.value
  end

  def terminated?(interpreter)
    values = @expression.evaluate(interpreter)

    raise(BASICExpressionError, 'Expression error') unless values.size == 1

    result = values[0]
    result = BooleanConstant.new(result.to_b) unless result.boolean_constant?

    result.value
  end
end

# Helper class for FOR-WHILE/NEXT
class ForWhileControl < AbstractForControl
  attr_reader :end

  def initialize(control, start, step, expression, start_line_stmt_mod)
    super(control, start, step, start_line_stmt_mod)

    @expression = expression
  end

  def front_terminated?(interpreter)
    values = @expression.evaluate(interpreter)

    raise(BASICExpressionError, 'Expression error') unless values.size == 1

    result = values[0]
    result = BooleanConstant.new(result.to_b) unless result.boolean_constant?

    !result.value
  end

  def terminated?(interpreter)
    values = @expression.evaluate(interpreter)

    raise(BASICExpressionError, 'Expression error') unless values.size == 1

    result = values[0]
    result = BooleanConstant.new(result.to_b) unless result.boolean_constant?

    !result.value
  end
end

# the interpreter
class Interpreter
  attr_writer :program
  attr_reader :current_line_stmt_mod
  attr_accessor :next_line_stmt_mod
  attr_reader :console_io
  attr_reader :trace_out
  attr_reader :start_time

  def initialize(console_io)
    @randomizer = Random.new(1)
    randomize_option = $options['randomize']
    respect_option = $options['respect_randomize']
    @randomizer = Random.new if randomize_option.value && respect_option.value

    @quotes = ['"']
    @console_io = console_io
    longnames_option = $options['long_names']
    @tokenbuilders = make_debug_tokenbuilders(longnames_option)

    @null_out = NullOut.new

    @line_breakpoints = {}
    @line_cond_breakpoints = {}
    @locked_variables = []
    @fornext_stack = []
    @data_store = DataStore.new
    @file_handlers = {}
    @return_stack = []
    @fornexts = {}
    @dimensions = {}
    @default_args = {}
    @variables = {}
    @user_function_defs = {}
    @user_function_lines = {}
    @user_var_values = []

    @function_stack = []
    @errorgoto_stack = []
    @resume_stack = []
    @error_stack = []

    @get_value_seen = []
    @running = false
    @start_time = Time.now
  end

  private

  def make_debug_tokenbuilders(longnames_option)
    tokenbuilders = []

    keywords =
      %w[
        GO STOP STEP BREAK NOBREAK
        LIST PRETTY DELETE PROFILE
        DIM GOTO LET PRINT
      ]

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

    user_function_names = FunctionFactory.user_function_names
    tokenbuilders <<
      ListTokenBuilder.new(user_function_names, UserFunctionToken)

    tokenbuilders << TextTokenBuilder.new(@quotes)
    tokenbuilders << NumberTokenBuilder.new
    tokenbuilders << IntegerTokenBuilder.new

    long_names = longnames_option.value
    tokenbuilders << VariableTokenBuilder.new(long_names)
    tokenbuilders << ListTokenBuilder.new(%w[TRUE FALSE], BooleanConstantToken)

    tokenbuilders << WhitespaceTokenBuilder.new
  end

  def verify_next_line_stmt_mod
    raise BASICSyntaxError, 'Program terminated without END' if
      @next_line_stmt_mod.nil?

    return if @program.line_number?(@next_line_stmt_mod.line_number)

    raise(BASICSyntaxError, "Line number #{@next_line_stmt_mod.line_number} not found")
  end

  public

  def program_new
    @program.clear
  end

  def program_loaded?
    !@program.lines.empty?
  end

  def program_okay?
    @program.okay?
  end

  def program_parse(args)
    @program.parse(args)
  end

  def program_list(args, list_tokens)
    @program.list(args, list_tokens)
  end

  def program_pretty(args, pretty_multiline)
    @program.pretty(args, pretty_multiline)
  end

  def program_delete(args)
    @program.delete(args)
  end

  def program_profile(args, show_timing)
    @program.profile(args, show_timing)
  end

  def program_crossref
    @program.crossref
  end

  def program_analyze
    @program.optimize(self)
    @program.analyze
  end

  def program_renumber(args)
    renumber_map = @program.renumber(args)
    renumber_breakpoints(renumber_map)
  end

  def program_store_line(line, print_seq_errors, print_errors)
    @program.store_line(line, print_seq_errors, print_errors)
  end

  def program_clear
    @program.clear
  end

  def program_check
    errors = @program.check
    errors.empty?
  end

  def print_program_errors
    errors = @program.errors

    errors.each { |error| @console_io.print_line(error) }
  end

  def program_save
    @program.save
  end

  def run
    raise(BASICCommandError, 'No program loaded') if @program.empty?

    unless @program.errors.empty?
      text = @program.errors.join('\n')
      raise(BASICCommandError, text)
    end
    
    # if breakpoint error, raise error
    errors = check_breakpoints(@program.lines)

    unless errors.empty?
      text = errors.join('\n')
      raise(BASICCommandError, text)
    end

    @program.reset_profile_metrics

    @step_mode = false
    trace = $options['trace'].value
    @trace_out = trace ? @console_io : @null_out

    @variables = {}
    @data_store.reset
    @user_function_defs = {}
    @user_function_lines = @program.assign_function_markers

    @previous_stack = []
    clear_previous_lines
    @start_time = Time.now
    run_program
  end

  def run_program
    if @program.check_for_errors(self) &&
       @program.optimize(self)
       @program.init_data(self)
      begin
        # run each statement
        # start with the first line number
        @current_line_stmt_mod = find_first_statement
        @running = true

        execute_step while @running
      rescue Interrupt
        stop_running
      end

      close_all_files
    end
  end

  def chain_to(filename)
    File.open(filename, 'r') do |file|
      program_clear
      file.each_line do |line|
        line = console_io.ascii_printables(line)
        program_store_line(line, false, false)
      end
    end
    program_check
  rescue Errno::ENOENT, Errno::EISDIR
    raise BASICRuntimeError.new(:te_no_chain, filename)
  end

  def chain(tokens)
    raise(BASICSyntaxError, 'Cannot CHAIN in a user function.') unless
      @function_stack.empty?

    @fornexts = {}
    @return_stack = []
    @user_function_defs = {}
    @user_function_lines = {}
    @user_var_values = []

    filename, _keywords = parse_args(tokens)

    chain_to(filename)

    raise(BASICSyntaxError, 'Cannot start CHAIN program') unless
      program_okay?

    @next_line_stmt_mod = find_first_statement
  end

  private

  def close_all_files
    @file_handlers.each { |_, fh| fh.close }
  end

  def find_first_statement
    # set next line to first statement
    line_number = @program.first_line_number
    line = @program.lines[line_number]
    statements = line.statements
    modifier = 0

    # start with the modifier, if any
    unless statements.empty?
      statement = statements[0]
      modifier = statement.start_index
    end

    LineStmtMod.new(line_number, 0, modifier)
  end

  public

  def rerun
    @variables = {}

    @function_stack = []
    @function_running = false

    @data_store.reset

    close_all_files

    @next_line_stmt_mod = find_first_statement
  end

  def seterrorgoto(line_number)
    if line_number.nil? || line_number.zero?
      # discard the current error handler
      @errorgoto_stack.pop
    else
      # if errorgoto stack is larger than resume stack
      # then we replace the top entry
      # if not, we are in main or an error handler and we add the entry
      @errorgoto_stack.pop if @errorgoto_stack.size > @resume_stack.size
      @errorgoto_stack << LineStmtMod.new(line_number, 0, 0)
    end
  end

  def resume(line_number)
    raise(BASICSyntaxError, 'RESUME without ON ERROR GOTO') if
      @resume_stack.empty?

    if line_number.nil?
      # set next line index from @resume_stack[-1]
      @next_line_stmt_mod = @resume_stack.pop
      @error_stack.pop
    else
      # set next line index from parameter
      @resume_stack.pop
      @error_stack.pop
      @next_line_stmt_mod = LineStmtMod.new(line_number, 0, 0)
    end
  end

  def print_errors(line_number, statement)
    @console_io.print_line("Errors in line #{line_number}:")
    statement.print_errors(@console_io)
  end

  def execute_a_statement
    detect = $options['detect_infinite_loop'].value

    raise(BASICSyntaxError, 'Infinite loop detected') if
      detect && @previous_line_indexes.include?(@current_line_stmt_mod)

    @previous_line_indexes << @current_line_stmt_mod

    line_number = @current_line_stmt_mod.line_number
    line = @program.lines[line_number]
    statements = line.statements
    statement_index = @current_line_stmt_mod.statement
    statement = statements[statement_index]

    statement.execute_a_statement(
      self, @trace_out, @current_line_stmt_mod, @function_running
    )
  end

  def current_user_function
    return nil if @function_stack.empty?

    @function_stack[-1][0]
  end

  def run_user_function(name)
    line_index = @user_function_lines[name]

    raise(BASICSyntaxError, "Function #{name} not defined") if line_index.nil?

    @function_stack.push [name.to_s, @current_line_stmt_mod, @next_line_stmt_mod]
    @previous_stack.push @previous_line_indexes
    @previous_line_indexes = []

    # run program at line_index
    @current_line_stmt_mod = line_index
    @function_running = true

    begin
      execute_step while @running && @function_running
    rescue Interrupt
      stop_running
    end

    @previous_line_indexes = @previous_stack.pop
    _, @current_line_stmt_mod, @next_line_stmt_mod = @function_stack.pop

    # one user-def function may invoke a second
    @function_running = !@function_stack.empty?
  end

  def exit_user_function
    @function_running = false
  end

  def execute_debug_command(keyword, args, cmd)
    case keyword.to_s
    when 'GO'
      raise(BASICCommandError, 'Too many arguments') unless args.empty?

      @debug_done = true
    when 'STOP'
      raise(BASICCommandError, 'Too many arguments') unless args.empty?

      @debug_done = true
      stop_running
    when 'STEP'
      raise(BASICCommandError, 'Too many arguments') unless args.empty?

      @step_mode = true
      @debug_done = true
    when 'BREAK'
      set_breakpoints(args)
    when 'NOBREAK'
      clear_breakpoints(args)
    when 'LIST'
      @program.list(args, false)
    when 'PRETTY'
      @program.pretty(args, false)
    when 'DELETE'
      @program.enblank(args)
    when 'PROFILE'
      @program.profile(args, false)
    when 'GOTO'
      statement = GotoStatement.new(nil, [keyword], [args])
      if statement.errors.empty?
        statement.execute(self)
      else
        statement.errors.each { |error| @console_io.print_line(error) }
      end
    when 'LET'
      statement = LetStatement.new(nil, [keyword], [args])
      if statement.errors.empty?
        statement.execute(self)
      else
        statement.errors.each { |error| @console_io.print_line(error) }
      end
    when 'PRINT'
      statement = PrintStatement.new(nil, [keyword], [args])
      if statement.errors.empty?
        statement.execute_core(self)
      else
        statement.errors.each { |error| @console_io.print_line(error) }
      end
    else
      print "Unknown command #{cmd}\n"
    end
  rescue BASICCommandError => e
    @console_io.print_line(e.to_s)
  end

  def debug_shell
    current_line_number = @current_line_stmt_mod.line_number
    line = @program.lines[current_line_number]
    @console_io.newline_when_needed
    text = current_line_number.to_s + ': ' + line.pretty(false).join('')
    @console_io.print_line(text)
    @step_mode = false
    @debug_done = false

    until @debug_done
      promptd = $options['promptd'].value
      @console_io.print_item(promptd)
      @console_io.newline if promptd.size > 1
      cmd = @console_io.read_line

      # tokenize
      invalid_tokenbuilder = InvalidTokenBuilder.new
      tokenizer = Tokenizer.new(@tokenbuilders, invalid_tokenbuilder)
      tokens = tokenizer.tokenize(cmd)
      tokens.delete_if(&:whitespace?)

      next if tokens.empty?

      keyword = tokens[0]
      args = tokens[1..-1]

      if keyword.keyword?
        execute_debug_command(keyword, args, cmd)
      else
        print "Unknown command #{cmd}\n"
      end
    end
  end

  def execute_step
    # pick the next line number
    @next_line_stmt_mod =
      @program.find_next_line_stmt_mod(@current_line_stmt_mod)

    next_line_stmt_mod = nil
    next_line_stmt_mod =
      @next_line_stmt_mod.clone unless @next_line_stmt_mod.nil?

    line_number = @current_line_stmt_mod.line_number
    line_statement = @current_line_stmt_mod.statement
    line_index = @current_line_stmt_mod.index

    # breakpoint may have already been set by another test
    breakpoint = false

    # look for line breakpoint
    if line_index.zero? &&
       line_statement.zero? &&
       @line_breakpoints.key?(line_number)
      breakpoint = true
    end

    unless breakpoint
      if @line_cond_breakpoints.key?(line_number)
        expressions = @line_cond_breakpoints[line_number]

        expressions.each do |expression|
          results = expression.evaluate(self)
          result = results[0]
          breakpoint = true if result.value
        end
      end
    end

    # check step mode
    breakpoint = true if @step_mode

    # debug shell may change @next_line_stmt_mod
    debug_shell if breakpoint

    # if next line number has changed, debug_shell executed a GOTO
    if @next_line_stmt_mod != next_line_stmt_mod
      @current_line_stmt_mod = @next_line_stmt_mod
      @next_line_stmt_mod = @program.find_next_line_stmt_mod(@current_line_stmt_mod)
    end

    begin
      execute_a_statement
      @get_value_seen = []

      # set the next line number
      @current_line_stmt_mod = nil

      if @running
        verify_next_line_stmt_mod
        @current_line_stmt_mod = @next_line_stmt_mod
      end
    rescue BASICTrappableError => e
      @console_io.newline_when_needed

      if @errorgoto_stack.size > @resume_stack.size
        @resume_stack << @current_line_stmt_mod
        @error_stack << e.code
        @current_line_stmt_mod = @errorgoto_stack[-1]
      else
        if @current_line_stmt_mod.nil?
          @console_io.print_line("Error #{e.code} #{e.message}")
        else
          line_number = @current_line_stmt_mod.line_number
          @console_io.print_line("Error #{e.code} #{e.message} in line #{line_number}")
        end

        stop_running
      end
    rescue BASICSyntaxError => e
      @console_io.newline_when_needed

      if @current_line_stmt_mod.nil?
        @console_io.print_line(e.message)
      else
        line_number = @current_line_stmt_mod.line_number
        @console_io.print_line("#{e.message} in line #{line_number}")
      end
      stop_running
    end
  end

  def split_breakpoint_tokens(tokens)
    tokens_lists = []
    tokens_list = []

    tokens.each do |token|
      if token.separator?
        tokens_lists << tokens_list unless tokens.empty?
        tokens_list = []
      else
        tokens_list << token
      end
    end

    tokens_lists << tokens_list unless tokens.empty?

    tokens_lists
  end

  def set_breakpoints(tokens)
    texts = []

    if tokens.empty?
      # print breakpoints
      @line_breakpoints.keys.sort.each do |bp|
        texts << "BREAK #{bp}"
      end
      @line_cond_breakpoints.keys.sort.each do |bp|
        expressions = @line_cond_breakpoints[bp]
        expressions.each do |expression|
          texts << "BREAK #{bp} IF #{expression}"
        end
      end
    else
      # kinds of breakpoints
      #  line - break before execution of line
      #  line condition - break before line if condition is true
      #  condition - break on any line if condition is true
      #  variable - break when contents change
      tokens_lists = split_breakpoint_tokens(tokens)

      tokens_lists.each do |tokens_list|
        if tokens_list.size == 1
          begin
            number = IntegerConstant.new(tokens_list[0])
            line_number = LineNumber.new(number)
            @line_breakpoints[line_number] = ''
          rescue BASICSyntaxError
            tkns = tokens_list.map(&:to_s).join

            raise BASICCommandError.new('INVALID BREAKPOINT ' + tkns)
          end
        else # tokens_list.size > 1
          begin
            number = IntegerConstant.new(tokens_list[0])
            line_number = LineNumber.new(number)

            raise(BASICSyntaxError, 'Invalid expression') unless
              tokens_list[1].keyword? && tokens_list[1].to_s == 'IF'

            raise(BASICExpressionError, 'Empty expression') unless
              tokens_list.size > 2
            
            expr_tokens = tokens_list[2..-1]
            expression = ValueExpressionSet.new(expr_tokens, :scalar)
            if @line_cond_breakpoints.key?(line_number)
              @line_cond_breakpoints[line_number] << expression
            else
              @line_cond_breakpoints[line_number] = [expression]
            end
          rescue BASICSyntaxError, BASICExpressionError
            tkns = tokens_list.map(&:to_s).join

            raise BASICCommandError.new('INVALID BREAKPOINT ' + tkns)
          end
        end
      end
    end

    texts
  end

  def clear_breakpoints(tokens)
    texts = []

    if tokens.empty?
      # print breakpoints
      @line_breakpoints.keys.sort.each do |bp|
        texts << "BREAK #{bp}"
      end
      @line_cond_breakpoints.keys.sort.each do |bp|
        expressions = @line_cond_breakpoints[bp]
        expressions.each do |expression|
          texts << "BREAK #{bp} IF #{expression}"
        end
      end
    else
      tokens_lists = split_breakpoint_tokens(tokens)
      tokens_lists.each do |tokens_list|
        if tokens_list.size == 1
          begin
            number = IntegerConstant.new(tokens_list[0])
            line_number = LineNumber.new(number)
            # TODO: distinguish between line and condition breakpoints
            @line_breakpoints.delete(line_number)
            @line_cond_breakpoints.delete(line_number)
          rescue BASICSyntaxError
            tkns = tokens_list.map(&:to_s).join

            raise BASICCommandError.new('INVALID BREAKPOINT ' + tkns)
          end
        else
          # TODO: remove a conditional breakpoint
          tkns = tokens_list.map(&:to_s).join

          raise BASICCommandError.new('INVALID BREAKPOINT ' + tkns)
        end
      end
    end

    texts
  end

  def clear_all_breakpoints
    @line_breakpoints = {}
    @line_cond_breakpoints = {}
  end

  def check_breakpoints(lines)
    errors = []

    @line_breakpoints.keys.each do |bp_line|
      errors << 'Breakpoint for non-existent line ' + bp_line.to_s unless
        lines.key?(bp_line)
    end

    @line_cond_breakpoints.keys.each do |bp_line|
      errors << 'Breakpoint for non-existent line ' + bp_line.to_s unless
        lines.key?(bp_line)
    end

    errors
  end

  def renumber_breakpoints(renumber_map)
    new_breakpoints = {}

    @line_breakpoints.each do |line_number, _|
      condition = @line_breakpoints[line_number]
      new_line_number = renumber_map[line_number]
      new_breakpoints[new_line_number] = condition
    end

    @line_breakpoints = new_breakpoints
  end

  def line_number?(line_number)
    @program.line_number?(line_number)
  end

  def find_next_line
    @program.find_next_line(@current_line_stmt_mod)
  end

  def find_next_line_stmt
    @program.find_next_line_stmt(@current_line_stmt_mod)
  end

  def find_next_line_stmt_mod
    @program.find_next_line_stmt_mod(@current_line_stmt_mod)
  end

  def statement_start_index(line_number, _statement_index)
    line = @program.lines[line_number]

    return if line.nil?

    statements = line.statements
    statement = statements[0]
    statement.start_index unless statement.nil?
  end

  def set_action(name, v)
    $options[name].set(v)

    if name == 'trace'
      @trace_out = v ? @console_io : @null_out
    end

    @program.uncache if %w[cache_const_expr precision base].include?(name)
  end

  def push_option(name, v)
    $options[name].push(v)

    if name == 'trace'
      @trace_out = v ? @console_io : @null_out
    end

    @program.uncache if %w[cache_const_expr precision base].include?(name)
  end

  def pop_option(name)
    v = $options[name].pop

    if name == 'trace'
      @trace_out = v ? @console_io : @null_out
    end

    @program.uncache if %w[cache_const_expr precision base].include?(name)
  end

  def clear_variables
    @variables = {}
  end

  # get default arguments
  def default_args(name)
    @default_args[name]
  end

  def set_default_args(name, args)
    @default_args[name] = args
  end

  # returns an Array of values
  def evaluate(expressions)
    result_values = []

    expressions.each do |expression|
      stack = expression.evaluate(self)
      act = stack.length
      exp = expression.empty? ? 0 : 1

      raise(BASICExpressionError, 'Bad expression') if act != exp

      # verify each item is of correct type
      result_values.concat stack
    end

    result_values
  end

  def dump_vars
    @variables.each do |name, dict|
      value = dict['value']
      @console_io.print_line("#{name}: #{value}")
    end

    @console_io.newline
  end

  def dump_user_functions
    @user_function_defs.each do |name, expression|
      # TODO: if multistatement function, print 'MULTISTATEMENT'
      @console_io.print_line("#{name}: #{expression}")
    end

    @console_io.newline
  end

  def dump_dims
    @dimensions.each do |variable_name, value|
      dims = []
      value.each { |nc| dims << nc.to_v }
      @console_io.print_line("#{variable_name} (#{dims.join(', ')})")
    end
  end

  def stop
    stop_running
    @console_io.print_line("STOP in line #{@current_line_stmt_mod.line_number}")
  end

  def stop_running
    @running = false
  end

  def rand(upper_bound)
    upper_bound = upper_bound.to_v
    upper_bound = upper_bound.truncate
    upper_bound = 1 if upper_bound <= 0
    upper_bound = 1 if $options['ignore_rnd_arg'].value
    upper_bound = upper_bound.to_f

    clear_previous_lines

    @randomizer.rand(upper_bound)
  end

  # set a new randomizer (unless option says to ignore)
  def new_random
    @randomizer = Random.new if $options['respect_randomize'].value
  end

  # get the current value for ERL()
  def error_line(part)
    raise BASICRuntimeError.new(:te_erl_no_err) if @resume_stack.empty?

    line_index = @resume_stack[-1]

    case part.to_i
    when 0
      value = line_index.line_number
    when 1
      value = line_index.statement
    when 2
      value = line_index.index
    else
      raise BASICRuntimeError.new(:te_val_out, 'ERL')
    end

    NumericConstant.new(value.to_i)
  end

  # get the current value for ERR()
  def error_code
    raise BASICRuntimeError.new(:te_err_no_err) if @error_stack.empty?

    code = @error_stack[-1]
    NumericConstant.new(code)
  end

  def set_dimensions(variable, subscripts)
    variable_name = variable.name
    int_subscripts = normalize_subscripts(subscripts)

    int_subscripts.each do |subscript|
      raise BASICRuntimeError.new(:te_subscript_out, variable_name.to_s) if
        subscript.to_i > $options['max_dim'].value
    end

    @dimensions[variable_name] = int_subscripts
  end

  def normalize_subscripts(subscripts)
    raise(BASICSyntaxError, 'Invalid subscripts container') unless
      subscripts.class.to_s == 'Array'

    int_subscripts = []

    subscripts.each do |subscript|
      raise(BASICExpressionError, "Invalid subscript #{subscript}") unless
        subscript.numeric_constant?

      int_subscripts << subscript.truncate
    end

    int_subscripts
  end

  def wrap_subscripts(variable_name, subscripts)
    raise(BASICSyntaxError, 'Invalid subscripts container') unless
      subscripts.class.to_s == 'Array'

    count = subscripts.count

    # upper bounds
    upper_values = make_dimensions(variable_name, count)
    uppers = []
    upper_values.each { |uv| uppers << uv.to_i }

    # lower bound
    lower = $options['base'].value

    wrapped_subscripts = []

    subscripts.each_with_index do |subscript, index|
      raise(BASICExpressionError, "Invalid subscript #{subscript}") unless
        subscript.numeric_constant?

      span = uppers[index] - lower + 1
      wrapped = subscript.to_i
      wrapped -= span if wrapped > uppers[index]
      wrapped += span if wrapped < lower
      wrapped_subscripts << NumericConstant.new(wrapped)
    end

    wrapped_subscripts
  end

  def get_dimensions(variable_name)
    @dimensions[variable_name]
  end

  def dimensions?(variable_name)
    @dimensions.key?(variable_name)
  end

  def set_user_function(name, sigils, definition)
    signature = name.to_s + '(' + sigils.join(',') + ')'

    raise BASICRuntimeError.new(:te_func_alr, signature) if
      @user_function_defs.key?(signature)

    @user_function_defs[signature] = definition
  end

  def get_user_function(name, sigils)
    signature = name.to_s + '(' + sigils.join(',') + ')'

    raise BASICRuntimeError.new(:te_func_no, signature) unless
      @user_function_defs.key?(signature)

    @user_function_defs[signature]
  end

  def define_user_var_values(names_and_values)
    @user_var_values.push(names_and_values)
  end

  def clear_user_var_values
    @user_var_values.pop
  end

  private

  def make_dimensions(variable_name, count)
    if @dimensions.key?(variable_name)
      @dimensions[variable_name]
    else
      Array.new(count, NumericConstant.new(10))
    end
  end

  public

  def check_subscripts(variable_name, subscripts, wrapped_subscripts)
    int_subscripts = normalize_subscripts(subscripts)

    # upper bounds
    dimensions = make_dimensions(variable_name, int_subscripts.size)

    raise(BASICSyntaxError, 'Incorrect number of subscripts') if
      int_subscripts.size != dimensions.size

    # lower bound
    lower_value = $options['base'].value
    lower = NumericConstant.new(lower_value)

    ss = subscripts
    ss = wrapped_subscripts if $options['wrap'].value

    # check subscript value against lower and upper bounds
    ss.each_with_index do |subscript, index|
      if subscript < lower
        raise BASICRuntimeError.new(:te_subscript_out, subscript.to_s)
      end

      if subscript > dimensions[index]
        raise BASICRuntimeError.new(:te_subscript_out, subscript.to_s)
      end
    end
  end

  def get_value(variable)
    legals = %w[Variable UserFunctionName]

    raise(BASICSyntaxError,
          "#{variable.class}:#{variable} is not a variable") unless
      legals.include?(variable.class.to_s)

    value = nil

    # first look in user function values stack
    length = @user_var_values.length

    if length > 0
      names_and_values = @user_var_values[-1]
      value = names_and_values[variable.name]
    end

    # then look in general table
    if value.nil?
      var = variable.to_sw
      default_type = variable.content_type
      default_value = NumericConstant.new(0)

      default_value = TextConstant.new('') if
        default_type == :string

      unless @variables.key?(var)
        if $options['require_initialized'].value
          raise BASICRuntimeError.new(:te_var_uninit, var)
        end

        # define a value for this variable
        @variables[var] =
          {
            'provenance' => @current_line_stmt_mod,
            'value' => default_value
          }
      end

      dict = @variables[var]
      value = dict['value']
      provenance = dict['provenance']
    end

    seen = @get_value_seen.include?(variable)

    trace = $options['trace'].value

    if trace && !seen
      provenance_option = $options['provenance'].value

      if provenance_option && !provenance.nil?
        text = ' ' + variable.to_s + ': (' + provenance.to_s + ') ' + value.to_s
      else
        text = ' ' + variable.to_s + ': ' + value.to_s
      end

      @trace_out.newline_when_needed
      @trace_out.print_line(text)
      @get_value_seen << variable
    end

    value
  end

  def set_value(variable, value)
    legals = %w[Variable UserFunction]

    raise(BASICSyntaxError,
          "#{variable.class}:#{variable} is not a variable name") unless
      legals.include?(variable.class.to_s)

    raise(BASICSyntaxError,
          "#{variable.class}:#{variable} is not a scalar variable name") if
      variable.class.to_s == 'VariableName' && !variable.scalar?

    if $options['lock_fornext'].value &&
       @locked_variables.include?(variable)
      raise BASICRuntimeError.new(:te_var_lock, variable.to_s)
    end

    # convert a numeric to a string when a string is expected
    if value.numeric_constant? &&
       variable.content_type == :string
      value = TextConstant.new(value.symbol_text)
    end

    # convert an integer to a numeric
    if value.content_type == :numeric &&
       variable.content_type == :integer
      token = IntegerConstantToken.new(value.to_s)
      value = IntegerConstant.new(token)
    end

    # convert a numeric to an integer
    if value.content_type == :integer &&
       variable.content_type == :numeric
      token = NumericConstantToken.new(value.to_s)
      value = NumericConstant.new(token)
    end

    # convert a boolean to an integer
    if value.content_type == :boolean &&
       variable.content_type == :numeric
      token = NumericConstantToken.new(value.to_i)
      value = NumericConstant.new(token)
    end

    # check that value type matches variable type
    unless variable.compatible?(value)
      raise(BASICSyntaxError,
            "Type mismatch '#{value}' is not #{variable.content_type}")
    end

    var = variable.to_sw

    if @variables.key?(var)
      dict = @variables[var]
      old_value = dict['value']
      old_provenance = dict['provenance']
      # a different value resets 'infinite loop' check
      if value != old_value || @current_line_stmt_mod != old_provenance
        clear_previous_lines
      end
    else
      # no prior value is a new value
      clear_previous_lines
    end

    dict = { 'provenance' => @current_line_stmt_mod, 'value' => value }
    @variables[var] = dict

    @trace_out.newline_when_needed
    @trace_out.print_line(' ' + variable.to_s + ' = ' + value.to_s)
  end

  def set_values(name, values)
    values.each do |coords, value|
      shape = :scalar
      shape = :array if coords.size == 1
      shape = :matrix if coords.size == 2
      wcoords = wrap_subscripts(name, coords)
      variable = Variable.new(name, shape, coords, wcoords)
      set_value(variable, value)
    end
  end

  def forget_value(variable)
    legals = %w[Variable]

    raise(BASICSyntaxError,
          "#{variable.class}:#{variable} is not a variable name") unless
      legals.include?(variable.class.to_s)

    raise(BASICSyntaxError,
          "#{variable.class}:#{variable} is not a scalar variable name") if
      variable.class.to_s == 'VariableName' && !variable.scalar?

    if $options['lock_fornext'].value &&
       @locked_variables.include?(variable)
      raise BASICRuntimeError.new(:te_var_lock, variable.to_s)
    end

    v = variable.to_s

    unless @variables.key?(v)
      if $options['require_initialized'].value
        raise BASICRuntimeError.new(:te_var_uninit, v)
      end
    end

    # removing a variable is a change
    clear_previous_lines if @variables.key?(v)

    @variables.delete(v)

    @trace_out.newline_when_needed
    @trace_out.print_line(' ' + v)
  end

  def forget_compound_values(variable)
    legals = %w[Variable]

    raise(BASICSyntaxError,
          "#{variable.class}:#{variable} is not a variable name") unless
      legals.include?(variable.class.to_s)

    raise(BASICSyntaxError,
          "#{variable.class}:#{variable} is not a scalar variable name") if
      variable.class.to_s == 'VariableName' && !(variable.array? || variable.matrix?)

    variable_name = variable.name
    vname_s = variable_name.to_s

    dims = @dimensions[variable_name]

    raise BASICRuntimeError.new(:te_var_uninit, vname_s) if
      dims.nil? && $options['require_initialized']

    if variable.array?
      vs = []

      # get names of known variables that start with variable name and no comma
      @variables.keys.each do |v|
        vname1_s, subs_s = v.split('(')
        vs << v if vname1_s == vname_s && !subs_s.include?(',')
      end

      # remove each one of them
      vs.each do |v|
        # example a3(14)
        # remove close parens a3(14
        v = v.chop
        # split on open parens e4 12,65
        vname1_s, subs_s = v.split('(')
        vtoken1 = VariableToken.new(vname1_s)
        vname1 = VariableName.new(vtoken1)
        # convert subscript to numeric
        sub1_token = NumericConstantToken.new(subs_s)
        sub1 = NumericConstant.new(sub1_token)
        subscripts = [sub1]
        # don't wrap subscripts for FORGET
        wsubscripts = subscripts
        variable = Variable.new(vname1, :scalar, subscripts, wsubscripts)
        forget_value(variable)
      end
    end

    if variable.matrix?
      vs = []

      # get names of known variables that start with variable name and no comma
      @variables.keys.each do |v|
        vname1_s, subs_s = v.split('(')
        vs << v if vname1_s == vname_s && subs_s.include?(',')
      end

      # remove each one of them
      vs.each do |v|
        # example e4(12,65)
        # remove close parens e4(12,65
        v = v.chop
        # split on open parens e4 12,65
        vname1_s, subs_s = v.split('(')
        vtoken1 = VariableToken.new(vname1_s)
        vname1 = VariableName.new(vtoken1)
        # split [1] on comma e4 12 65
        sub1_s, sub2_s = subs_s.split(',')
        # convert subscripts to numerics
        sub1_token = NumericConstantToken.new(sub1_s)
        sub1 = NumericConstant.new(sub1_token)
        sub2_token = NumericConstantToken.new(sub2_s)
        sub2 = NumericConstant.new(sub2_token)
        subscripts = [sub1, sub2]
        # don't wrap subscripts for FORGET
        wsubscripts = subscripts
        variable = Variable.new(vname1, :scalar, subscripts, wsubscripts)
        forget_value(variable)
      end
    end

    @dimensions.delete(variable_name)
  end

  def clear_previous_lines
    @previous_line_indexes = []
  end

  def lock_variable(variable)
    if @locked_variables.include?(variable)
      raise BASICRuntimeError.new(:te_var_lock2, variable.to_s)
    end

    @locked_variables << variable
  end

  def unlock_variable(variable)
    unless @locked_variables.include?(variable)
      raise BASICRuntimeError.new(:te_var_no_lock, variable.to_s)
    end

    @locked_variables.delete(variable)
  end

  def push_return(destination)
    @return_stack.push(destination)
  end

  def pop_return
    raise BASICRuntimeError.new(:te_ret_no_gos) if @return_stack.empty?

    # remove all lines from the subroutine in the 'visited' list
    while !@previous_line_indexes.empty? &&
          @previous_line_indexes[-1] != @return_stack[-1]
      @previous_line_indexes.pop
    end

    @return_stack.pop
  end

  def assign_fornext(fornext_control)
    control = fornext_control.control
    v = control.to_s
    fornext_control.forget = !@variables.key?(v)
    @fornexts[control] = fornext_control
    from = fornext_control.start
    set_value(control, from)
  end

  def retrieve_fornext(control)
    fornext = @fornexts[control]

    raise BASICRuntimeError.new(:te_next_no_for) if fornext.nil?

    fornext
  end

  def enter_fornext(variable)
    @fornext_stack.push(variable)
  end

  def exit_fornext(forget, control)
    raise BASICRuntimeError.new(:te_next_no_for) if @fornext_stack.empty?

    @fornext_stack.pop

    forget_value(control) if $options['forget_fornext'].value && forget
  end

  def top_fornext
    raise BASICRuntimeError.new(:te_inext_no_for) if @fornext_stack.empty?

    @fornext_stack[-1]
  end

  def add_file_names(file_names)
    file_names.each do |name|
      raise BASICRuntimeError.new(:te_fname_inv, name.to_s) unless
        name.content_type == :string

      raise BASICRuntimeError.new(:te_file_no_fnd, name.value.to_s) unless
        File.file?(name.to_v)

      file_handle = FileHandle.new(@file_handlers.size + 1)
      @file_handlers[file_handle] = FileHandler.new(name.value)
    end
  end

  def open_file(filename, fh, mode)
    raise BASICRuntimeError.new(:te_fname_inv, filename.to_s) unless
      filename.text_constant?

    ### todo: check for already open handle
    fhr = FileHandler.new(filename.to_v)
    fhr.set_mode(mode)
    @file_handlers[fh] = fhr
  end

  def close_file(fh)
    raise BASICRuntimeError.new(:te_fh_unk) unless @file_handlers.key?(fh)

    fhr = @file_handlers[fh]
    fhr.close
    @file_handlers.delete(fh)
  end

  def get_file_handler(file_handle, mode)
    return @console_io if file_handle.nil?

    raise BASICRuntimeError.new(:te_fh_unk) unless
      @file_handlers.key?(file_handle)

    fh = @file_handlers[file_handle]
    fh.set_mode(mode)

    fh
  end

  def get_data_store(file_handle)
    return @data_store if file_handle.nil?

    raise BASICRuntimeError.new(:te_fh_unk) unless
      @file_handlers.key?(file_handle)

    fh = @file_handlers[file_handle]
    fh.set_mode(:read)

    fh
  end
end
