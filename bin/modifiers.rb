# Modifier
class AbstractModifier
  def self.extra_keywords
    []
  end

  attr_reader :errors
  attr_reader :numerics
  attr_reader :strings
  attr_reader :booleans
  attr_reader :variables
  attr_reader :operators
  attr_reader :functions
  attr_reader :userfuncs
  attr_reader :comprehension_effort

  def initialize
    @errors = []
  end
end

# IF
class IfModifier < AbstractModifier
  def self.lead_keywords
    [
      [KeywordToken.new('IF')]
    ]
  end

  def initialize(expression_tokens)
    super()

    @expression = parse_expression(expression_tokens)
    @numerics = @expression.numerics
    @strings = @expression.strings
    @booleans = @expression.booleans
    @variables = @expression.variables
    @operators = @expression.operators
    @functions = @expression.functions
    @userfuncs = @expression.userfuncs
    @comprehension_effort = @expression.comprehension_effort
  end

  def pretty
    'IF ' + @expression.to_s
  end

  def dump
    lines = []

    lines += @expression.dump unless @expression.nil?
    lines += @statement.dump unless @statement.nil?
    lines += @else_stmt.dump unless @else_stmt.nil?

    lines
  end

  def pre_trace
    ' IF ' + @expression.to_s
  end

  def post_trace
    ' ENDIF'
  end

  def execute_pre(interpreter)
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
    current_line_index = interpreter.current_line_index
    number = current_line_index.number
    statement_index = current_line_index.statement
    index = current_line_index.index
    fail_index = -index
    destination = LineNumberIndex.new(number, statement_index, fail_index)
    interpreter.next_line_index = destination
  end

  def execute_post(_) end

  private

  def parse_expression(expression_tokens)
    expression = nil

    begin
      expression = ValueExpression.new(expression_tokens, :scalar)
    rescue BASICExpressionError => e
      @errors << e.message
    end

    expression
  end
end

# UNLESS
class UnlessModifier < AbstractModifier
  def self.lead_keywords
    [
      [KeywordToken.new('UNLESS')]
    ]
  end

  def initialize(expression_tokens)
    super()
    
    @expression = parse_expression(expression_tokens)
    @numerics = @expression.numerics
    @strings = @expression.strings
    @booleans = @expression.booleans
    @variables = @expression.variables
    @operators = @expression.operators
    @functions = @expression.functions
    @userfuncs = @expression.userfuncs
    @comprehension_effort = @expression.comprehension_effort
  end

  def pretty
    'UNLESS ' + @expression.to_s
  end

  def dump
    lines = []

    lines += @expression.dump unless @expression.nil?
    lines += @statement.dump unless @statement.nil?
    lines += @else_stmt.dump unless @else_stmt.nil?

    lines
  end

  def pre_trace
    ' UNLESS ' + @expression.to_s
  end

  def post_trace
    ' ENDUNLESS'
  end

  def execute_pre(interpreter)
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
    current_line_index = interpreter.current_line_index
    number = current_line_index.number
    statement_index = current_line_index.statement
    index = current_line_index.index
    fail_index = -index
    destination = LineNumberIndex.new(number, statement_index, fail_index)
    interpreter.next_line_index = destination
  end

  def execute_post(_) end

  private

  def parse_expression(expression_tokens)
    expression = nil

    begin
      expression = ValueExpression.new(expression_tokens, :scalar)
    rescue BASICExpressionError => e
      @errors << e.message
    end

    expression
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
    %w[TO STEP]
  end

  def initialize(control_and_start_tokens, end_tokens, step_tokens)
    super()

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
    @control = Variable.new(control_name, :scalar, [])
    @start = ValueExpression.new(start_tokens, :scalar)
    @end = ValueExpression.new(end_tokens, :scalar)

    @step = nil
    @step = ValueExpression.new(step_tokens, :scalar) unless step_tokens.nil?

    if @step.nil?
      @numerics = @start.numerics + @end.numerics
      @strings = @start.strings + @end.strings
      @booleans = @start.booleans + @end.booleans
      control = XrefEntry.new(@control.to_s, nil, true)
      @variables = [control] + @start.variables + @end.variables
      @operators = @start.operators + @end.operators
      @functions = @start.functions + @end.functions
      @userfuncs = @start.userfuncs + @end.userfuncs
    else
      @numerics = @start.numerics + @end.numerics + @step.numerics
      @strings = @start.strings + @end.strings + @step.strings
      @booleans = @start.booleans + @end.booleans + @step.booleans
      control = XrefEntry.new(@control.to_s, nil, true)

      @variables =
        [control] + @start.variables + @end.variables + @step.variables

      @operators = @start.operators + @end.operators + @step.operators
      @functions = @start.functions + @end.functions + @step.functions
      @userfuncs = @start.userfuncs + @end.userfuncs + @step.userfuncs
    end

    @comprehension_effort = @start.comprehension_effort
    @comprehension_effort += @end.comprehension_effort
    @comprehension_effort += @step.comprehension_effort unless @step.nil?
  end

  def pretty
    if @step.nil?
      "FOR #{@control} = #{@start} TO #{@end}"
    else
      "FOR #{@control} = #{@start} TO #{@end} STEP #{@step}"
    end
  end

  def dump
    lines = []
    lines << 'control: ' + @control.dump unless @control.nil?
    lines << 'start:   ' + @start.dump.to_s unless @start.nil?
    lines << 'end:     ' + @end.dump.to_s unless @end.nil?
    lines << 'step:    ' + @step.dump.to_s unless @step.nil?
    lines
  end

  def pre_trace
    if @step.nil?
      " FOR #{@control} = #{@start} TO #{@end}"
    else
      " FOR #{@control} = #{@start} TO #{@end} STEP #{@step}"
    end
  end

  def post_trace
    " NEXT #{@control}"
  end

  def execute_pre(interpreter)
    from = @start.evaluate(interpreter)[0]
    to = @end.evaluate(interpreter)[0]
    step = NumericConstant.new(1)
    step = @step.evaluate(interpreter)[0] unless @step.nil?

    fornext_control =
      interpreter.assign_fornext(@control, from, to, step)

    interpreter.lock_variable(@control)
    interpreter.enter_fornext(@control)
    terminated = fornext_control.front_terminated?

    io = interpreter.trace_out
    print_trace_info(io, terminated)

    return unless terminated

    # front-terminated; go to post-exec of this modifier
    interpreter.unlock_variable(@control)

    current_line_index = interpreter.current_line_index
    number = current_line_index.number
    statement_index = current_line_index.statement
    index = current_line_index.index
    for_index = -index
    destination = LineNumberIndex.new(number, statement_index, for_index)
    interpreter.next_line_index = destination
  end

  def execute_post(interpreter)
    fornext_control = interpreter.retrieve_fornext(@control)

    to = @end.evaluate(interpreter)[0]
    step = NumericConstant.new(1)
    step = @step.evaluate(interpreter)[0] unless @step.nil?

    terminated = fornext_control.terminated?(interpreter)
    io = interpreter.trace_out
    print_trace_info(io, terminated)

    if terminated
      interpreter.unlock_variable(@control)
      interpreter.exit_fornext(fornext_control.forget, fornext_control.control)
    else
      # set next line from top item
      interpreter.next_line_index = fornext_control.loop_start_index
      # change control variable value
      fornext_control.bump_control(interpreter)
    end
  end

  private

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
