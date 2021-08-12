# Modifier
class AbstractModifier
  def self.extra_keywords
    []
  end

  attr_reader :errors
  attr_reader :warnings
  attr_reader :numerics
  attr_reader :strings
  attr_reader :booleans
  attr_reader :variables
  attr_reader :operators
  attr_reader :functions
  attr_reader :userfuncs
  attr_reader :comprehension_effort
  attr_reader :profile_pre_count
  attr_reader :profile_post_count
  attr_reader :profile_pre_time
  attr_reader :profile_post_time

  def initialize(tokens_lists)
    @tokens = tokens_lists.flatten
    @errors = []
    @warnings = []
    @profile_pre_count = 0
    @profile_post_count = 0
    @profile_pre_time = 0
    @profile_post_time = 0
  end

  def reset_profile_metrics
    @profile_pre_count = 0
    @profile_post_count = 0
    @profile_pre_time = 0
    @profile_post_time = 0
  end

  def execute_pre(interpreter)
    timing = Benchmark.measure { execute_pre_stmt(interpreter) }

    user_time = timing.utime + timing.cutime
    sys_time = timing.stime + timing.cstime
    time = user_time + sys_time

    @profile_pre_time += time
    @profile_pre_count += 1
  end

  def execute_post(interpreter)
    timing = Benchmark.measure { execute_post_stmt(interpreter) }

    user_time = timing.utime + timing.cutime
    sys_time = timing.stime + timing.cstime
    time = user_time + sys_time

    @profile_post_time += time
    @profile_post_count += 1
  end

  private

  # get opposite modifier (pre- when in post; post- when in pre)
  def get_counterpart(interpreter)
    current_line_index = interpreter.current_line_index
    number = current_line_index.number
    statement_index = current_line_index.statement
    index = current_line_index.index
    other_index = -index
    LineNumberIndex.new(number, statement_index, other_index)
  end

  def execute_pre_stmt(_); end

  def execute_post_stmt(_); end
end

# IF
class IfModifier < AbstractModifier
  def self.lead_keywords
    [
      [KeywordToken.new('IF')]
    ]
  end

  def initialize(tokens_lists)
    super(tokens_lists)

    expression_tokens = tokens_lists.last
    @expression = ValueExpressionSet.new(expression_tokens, :scalar)
    @errors << 'TAB() not allowed' if @expression.has_tab
    @warnings << 'Constant expression' if @expression.constant

    @numerics = @expression.numerics
    @strings = @expression.strings
    @booleans = @expression.booleans
    @variables = @expression.variables
    @operators = @expression.operators
    @functions = @expression.functions
    @userfuncs = @expression.userfuncs
    @comprehension_effort = @expression.comprehension_effort
  end

  def uncache
    @expression.uncache
  end

  def pre_pretty
    ' IF ' + @expression.to_s
  end

  def post_pretty
    ' ENDIF'
  end

  def dump
    lines = []

    lines += @expression.dump unless @expression.nil?
    lines += @statement.dump unless @statement.nil?
    lines += @else_stmt.dump unless @else_stmt.nil?

    lines
  end

  def pre_trace
    'IF ' + @expression.to_s
  end

  def post_trace
    'ENDIF'
  end

  private

  def execute_pre_stmt(interpreter)
    io = interpreter.trace_out

    values = @expression.evaluate(interpreter)
    raise(BASICExpressionError, 'Too many values') unless
      values.size == 1

    result = values[0]
    result = BooleanConstant.new(result) unless
      result.class.to_s == 'BooleanConstant'

    s = ' ' + result.to_s
    io.trace_output(s)

    # if true then continue execution normally
    return if result.value

    # if false then transfer to our post modifier
    interpreter.next_line_index = get_counterpart(interpreter)
  end
end

# UNLESS
class UnlessModifier < AbstractModifier
  def self.lead_keywords
    [
      [KeywordToken.new('UNLESS')]
    ]
  end

  def initialize(tokens_lists)
    super

    expression_tokens = tokens_lists.last
    @expression = ValueExpressionSet.new(expression_tokens, :scalar)
    @errors << 'TAB() not allowed' if @expression.has_tab
    @warnings << 'Constant expression' if @expression.constant

    @numerics = @expression.numerics
    @strings = @expression.strings
    @booleans = @expression.booleans
    @variables = @expression.variables
    @operators = @expression.operators
    @functions = @expression.functions
    @userfuncs = @expression.userfuncs
    @comprehension_effort = @expression.comprehension_effort
  end

  def uncache
    @expression.uncache
  end

  def pre_pretty
    ' UNLESS ' + @expression.to_s
  end

  def post_pretty
    ' ENDUNLESS'
  end

  def dump
    lines = []

    lines += @expression.dump unless @expression.nil?
    lines += @statement.dump unless @statement.nil?
    lines += @else_stmt.dump unless @else_stmt.nil?

    lines
  end

  def pre_trace
    'UNLESS ' + @expression.to_s
  end

  def post_trace
    'ENDUNLESS'
  end

  private

  def execute_pre_stmt(interpreter)
    io = interpreter.trace_out

    values = @expression.evaluate(interpreter)
    raise(BASICExpressionError, 'Too many values') unless
      values.size == 1

    result = values[0]
    result = BooleanConstant.new(result) unless
      result.class.to_s == 'BooleanConstant'

    s = ' ' + result.to_s
    io.trace_output(s)
    
    # if false then continue execution normally
    return unless result.value

    # if true then transfer to our post modifier
    interpreter.next_line_index = get_counterpart(interpreter)
  end
end

# WHILE
class WhileModifier < AbstractModifier
  def self.lead_keywords
    [
      [KeywordToken.new('WHILE')]
    ]
  end

  def initialize(tokens_lists)
    super

    expression_tokens = tokens_lists.last
    @expression = ValueExpressionSet.new(expression_tokens, :scalar)
    @errors << 'TAB() not allowed' if @expression.has_tab
    @warnings << 'Constant expression' if @expression.constant

    @numerics = @expression.numerics
    @strings = @expression.strings
    @booleans = @expression.booleans
    @variables = @expression.variables
    @operators = @expression.operators
    @functions = @expression.functions
    @userfuncs = @expression.userfuncs
    @comprehension_effort = @expression.comprehension_effort
  end

  def uncache
    @expression.uncache
  end

  def pre_pretty
    ' WHILE ' + @expression.to_s
  end

  def post_pretty
    ' ENDWHILE'
  end

  def dump
    lines = []

    lines += @expression.dump unless @expression.nil?
    lines += @statement.dump unless @statement.nil?
    lines += @else_stmt.dump unless @else_stmt.nil?

    lines
  end

  def pre_trace
    'WHILE ' + @expression.to_s
  end

  def post_trace
    'ENDWHILE'
  end

  private
  
  def execute_pre_stmt(interpreter)
    io = interpreter.trace_out

    values = @expression.evaluate(interpreter)
    raise(BASICExpressionError, 'Too many values') unless
      values.size == 1

    result = values[0]
    result = BooleanConstant.new(result) unless
      result.class.to_s == 'BooleanConstant'

    s = ' ' + result.to_s
    io.trace_output(s)

    # if not terminated then continue execution normally
    return if result.value

    # if terminated then transfer to our post modifier
    interpreter.next_line_index = get_counterpart(interpreter)
  end

  def execute_post_stmt(interpreter)
    io = interpreter.trace_out

    values = @expression.evaluate(interpreter)
    raise(BASICExpressionError, 'Too many values') unless
      values.size == 1

    result = values[0]
    result = BooleanConstant.new(result) unless
      result.class.to_s == 'BooleanConstant'

    s = ' ' + result.to_s
    io.trace_output(s)

    # if terminated then continue to next statement
    return unless result.value

    # if not terminated then go to start of while
    interpreter.next_line_index = get_counterpart(interpreter)
  end
end

# UNTIL
class UntilModifier < AbstractModifier
  def self.lead_keywords
    [
      [KeywordToken.new('UNTIL')]
    ]
  end

  def initialize(tokens_lists)
    super

    expression_tokens = tokens_lists.last
    @expression = ValueExpressionSet.new(expression_tokens, :scalar)
    @errors << 'TAB() not allowed' if @expression.has_tab
    @warnings << 'Constant expression' if @expression.constant

    @numerics = @expression.numerics
    @strings = @expression.strings
    @booleans = @expression.booleans
    @variables = @expression.variables
    @operators = @expression.operators
    @functions = @expression.functions
    @userfuncs = @expression.userfuncs
    @comprehension_effort = @expression.comprehension_effort
  end

  def uncache
    @expression.uncache
  end

  def pre_pretty
    ' UNTIL ' + @expression.to_s
  end

  def post_pretty
    ' ENDUNTIL'
  end

  def dump
    lines = []

    lines += @expression.dump unless @expression.nil?
    lines += @statement.dump unless @statement.nil?
    lines += @else_stmt.dump unless @else_stmt.nil?

    lines
  end

  def pre_trace
    'UNTIL ' + @expression.to_s
  end

  def post_trace
    'ENDUNTIL'
  end

  private

  def execute_pre_stmt(interpreter)
    io = interpreter.trace_out

    values = @expression.evaluate(interpreter)
    raise(BASICExpressionError, 'Too many values') unless
      values.size == 1

    result = values[0]
    result = BooleanConstant.new(result) unless
      result.class.to_s == 'BooleanConstant'

    s = ' ' + result.to_s
    io.trace_output(s)

    @profile_pre_count += 1
    
    # if terminated then continue execution normally
    return unless result.value

    # if not terminated then transfer to our post modifier
    interpreter.next_line_index = get_counterpart(interpreter)
  end

  def execute_post_stmt(interpreter)
    io = interpreter.trace_out

    values = @expression.evaluate(interpreter)
    raise(BASICExpressionError, 'Too many values') unless
      values.size == 1

    result = values[0]
    result = BooleanConstant.new(result) unless
      result.class.to_s == 'BooleanConstant'

    s = ' ' + result.to_s
    io.trace_output(s)

    @profile_post_count += 1

    # if not terminated then continue to next statement
    return if result.value

    # if terminated then go to start of until
    interpreter.next_line_index = get_counterpart(interpreter)
  end
end

# FOR
class ForModifier < AbstractModifier
  def self.lead_keywords
    [
      [KeywordToken.new('FOR')]
    ]
  end

  def self.extra_keywords
    %w[STEP TO UNTIL WHILE]
  end

  def initialize(tokens_lists, control_and_start_tokens, step_tokens, end_tokens, until_tokens, while_tokens)
    super(tokens_lists)

    parts = split_on_token(control_and_start_tokens, '=')

    raise(BASICSyntaxError, 'Incorrect initialization') if
      parts.size != 3

    raise(BASICSyntaxError, 'Missing "=" sign') if
      parts[1].to_s != '='

    control_tokens = parts[0]
    start_tokens = parts[2]

    @errors << 'Control variable must be a variable' unless
      control_tokens.class.to_s == 'Array' &&
      !control_tokens.empty? &&
      control_tokens[0].variable?

    control_name = VariableName.new(control_tokens[0])
    @control = Variable.new(control_name, :scalar, [], [])
    @start = ValueExpressionSet.new(start_tokens, :scalar)

    @step = ValueExpressionSet.new(step_tokens, :scalar) unless
      step_tokens.nil?

    @end = ValueExpressionSet.new(end_tokens, :scalar) unless
      end_tokens.nil?

    unless until_tokens.nil?
      @until = ValueExpressionSet.new(until_tokens, :scalar)
      @warnings << 'Constant expression' if @until.constant
    end

    unless while_tokens.nil?
      @while = ValueExpressionSet.new(while_tokens, :scalar)
      @warnings << 'Constant expression' if @while.constant
    end

    @errors << 'TAB() not allowed' if !@start.nil? && @start.has_tab
    @errors << 'TAB() not allowed' if !@step.nil? && @step.has_tab
    @errors << 'TAB() not allowed' if !@end.nil? && @end.has_tab
    @errors << 'TAB() not allowed' if !@while.nil? && @while.has_tab
    @errors << 'TAB() not allowed' if !@until.nil? && @until.has_tab

    control = XrefEntry.new(@control.to_s, nil, true)

    @numerics = @start.numerics
    @strings = @start.strings
    @booleans = @start.booleans
    @variables = [control] + @start.variables
    @operators = @start.operators
    @functions = @start.functions
    @userfuncs = @start.userfuncs

    unless @end.nil?
      @numerics += @end.numerics
      @strings += @end.strings
      @booleans += @end.booleans
      @variables += @end.variables
      @operators += @end.operators
      @functions += @end.functions
      @userfuncs += @end.userfuncs
    end

    unless @step.nil?
      @numerics += @step.numerics
      @strings += @step.strings
      @booleans += @step.booleans
      @variables += @step.variables
      @operators += @step.operators
      @functions += @step.functions
      @userfuncs += @step.userfuncs
    end

    unless @until.nil?
      @numerics += @until.numerics
      @strings += @until.strings
      @booleans += @until.booleans
      @variables += @until.variables
      @operators += @until.operators
      @functions += @until.functions
      @userfuncs += @until.userfuncs
    end

    unless @while.nil?
      @numerics += @while.numerics
      @strings += @while.strings
      @booleans += @while.booleans
      @variables += @while.variables
      @operators += @while.operators
      @functions += @while.functions
      @userfuncs += @while.userfuncs
    end

    @comprehension_effort = @start.comprehension_effort
    @comprehension_effort += @end.comprehension_effort unless @end.nil?
    @comprehension_effort += @step.comprehension_effort unless @step.nil?
    @comprehension_effort += @until.comprehension_effort unless @until.nil?
    @comprehension_effort += @while.comprehension_effort unless @while.nil?
  end

  def uncache
    @start.uncache unless @start.nil?
    @end.uncache unless @end.nil?
    @step.uncache unless @step.nil?
    @until.uncache unless @unless.nil?
    @while.uncache unless @while.nil?
  end

  def pre_pretty
    text = ''
    
    unless @end.nil?
      if @step.nil?
        text = " FOR #{@control} = #{@start} TO #{@end}"
      else
        text = " FOR #{@control} = #{@start} TO #{@end} STEP #{@step}"
      end
    end

    unless @until.nil?
      if @step.nil?
        text = " FOR #{@control} = #{@start} UNTIL #{@until}"
      else
        text = " FOR #{@control} = #{@start} UNTIL #{@until} STEP #{@step}"
      end
    end

    unless @while.nil?
      if @step.nil?
        text = " FOR #{@control} = #{@start} WHILE #{@while}"
      else
        text = " FOR #{@control} = #{@start} WHILE #{@while} STEP #{@step}"
      end
    end

    text
  end

  def post_pretty
    ' NEXT'
  end

  def dump
    lines = []
    lines << 'control: ' + @control.dump unless @control.nil?
    lines << 'start:   ' + @start.dump.to_s unless @start.nil?
    lines << 'end:     ' + @end.dump.to_s unless @end.nil?
    lines << 'step:    ' + @step.dump.to_s unless @step.nil?
    lines << 'until:   ' + @until.dump.to_s unless @until.nil?
    lines << 'while:   ' + @while.dump.to_s unless @while.nil?
    lines
  end

  def pre_trace
    # notice that this output differs from pretty()
    # we have a leading space here

    s = ''

    unless @end.nil?
      if @step.nil?
        s = "FOR #{@control} = #{@start} TO #{@end}"
      else
        s = "FOR #{@control} = #{@start} TO #{@end} STEP #{@step}"
      end
    end

    unless @until.nil?
      if @step.nil?
        s = "FOR #{@control} = #{@start} UNTIL #{@until}"
      else
        s = "FOR #{@control} = #{@start} UNTIL #{@until} STEP #{@step}"
      end
    end

    unless @while.nil?
      if @step.nil?
        s = "FOR #{@control} = #{@start} UNTIL #{@while}"
      else
        s = "FOR #{@control} = #{@start} UNTIL #{@while} STEP #{@step}"
      end
    end

    s
  end

  def post_trace
    "NEXT #{@control}"
  end

  private

  def execute_pre_stmt(interpreter)
    from = @start.evaluate(interpreter)[0]
    step = NumericConstant.new(1)
    step = @step.evaluate(interpreter)[0] unless @step.nil?

    unless @end.nil?
      to = @end.evaluate(interpreter)[0]
      fornext_control = ForToControl.new(@control, from, step, to)
    end

    fornext_control = ForUntilControl.new(@control, from, step, @until) unless
      @until.nil?

    fornext_control = ForWhileControl.new(@control, from, step, @while) unless
      @while.nil?

    interpreter.assign_fornext(fornext_control)

    interpreter.lock_variable(@control) if $options['lock_fornext'].value
    interpreter.enter_fornext(@control)

    terminated = fornext_control.front_terminated?(interpreter)

    io = interpreter.trace_out
    print_trace_info(io, terminated)

    return unless terminated

    # front-terminated; go to post-exec of this modifier
    interpreter.unlock_variable(@control) if $options['lock_fornext'].value

    interpreter.next_line_index = get_counterpart(interpreter)
  end

  def execute_post_stmt(interpreter)
    fornext_control = interpreter.retrieve_fornext(@control)

    bump_early = fornext_control.bump_early?

    # change control variable value for FOR-WHILE and FOR-UNTIL
    fornext_control.bump_control(interpreter) if bump_early

    terminated = fornext_control.terminated?(interpreter)
    io = interpreter.trace_out
    print_trace_info(io, terminated)

    if terminated
      interpreter.unlock_variable(@control) if $options['lock_fornext'].value
      interpreter.exit_fornext(fornext_control.forget, fornext_control.control)
    else
      # set next line from top item
      interpreter.next_line_index = fornext_control.loop_start_index
      # change control variable value
      fornext_control.bump_control(interpreter) unless bump_early
    end
  end

  def split_on_token(tokens, token_to_split)
    results = []
    list = []

    tokens.each do |token|
      if token.to_s != token_to_split
        list << token
      else
        results << list unless list.empty?
        list = []
        results << token
      end
    end

    results << list unless list.empty?
    results
  end

  def print_trace_info(io, terminated)
    io.trace_output(" terminated:#{terminated}")
  end
end
