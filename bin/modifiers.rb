# IF
class IfModifier
  attr_reader :errors
  attr_reader :numerics
  attr_reader :strings
  attr_reader :variables
  attr_reader :operators
  attr_reader :functions
  attr_reader :userfuncs

  def initialize(expression_tokens)
    @errors = []
    @expression = parse_expression(expression_tokens)
    @numerics = @expression.numerics
    @strings = @expression.strings
    @variables = @expression.variables
    @operators = @expression.operators
    @functions = @expression.functions
    @userfuncs = @expression.userfuncs
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

# FOR
class ForModifier
  attr_reader :errors
  attr_reader :numerics
  attr_reader :strings
  attr_reader :variables
  attr_reader :operators
  attr_reader :functions
  attr_reader :userfuncs

  def initialize(control_and_start_tokens, end_tokens, step_tokens)
    @errors = []
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
      control = XrefEntry.new(@control.to_s, nil, true)
      @variables = [control] + @start.variables + @end.variables
      @operators = @start.operators + @end.operators
      @functions = @start.functions + @end.functions
      @userfuncs = @start.userfuncs + @end.userfuncs
    else
      @numerics = @start.numerics + @end.numerics + @step.numerics
      @strings = @start.strings + @end.strings + @step.strings
      control = XrefEntry.new(@control.to_s, nil, true)

      @variables =
        [control] + @start.variables + @end.variables + @step.variables

      @operators = @start.operators + @end.operators + @step.operators
      @functions = @start.functions + @end.functions + @step.functions
      @userfuncs = @start.userfuncs + @end.userfuncs + @step.userfuncs
    end
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
    start_values = @start.evaluate(interpreter)
    start_value = start_values[0]
    @current_value = start_value if @current_value.nil?
    interpreter.set_value(@control, @current_value)
    endvs = @end.evaluate(interpreter)
    endv = endvs[0]

    if @step.nil?
      step = NumericConstant.new(1)
    else
      steps = @step.evaluate(interpreter)
      step = steps[0]
    end

    interpreter.lock_variable(@control)
    interpreter.enter_fornext(@control)
    terminated = terminated?(@current_value, step, endv)

    io = interpreter.trace_out
    print_trace_info(io, terminated)

    return unless terminated

    # front-terminated; go to next statement or modifier
    interpreter.unlock_variable(@control)
    interpreter.exit_fornext
    @current_value = nil

    current_line_index = interpreter.current_line_index
    number = current_line_index.number
    statement_index = current_line_index.statement
    index = current_line_index.index
    for_index = -index
    destination = LineNumberIndex.new(number, statement_index, for_index)
    interpreter.next_line_index = destination
  end

  def execute_post(interpreter)
    endvs = @end.evaluate(interpreter)
    endv = endvs[0]

    if @step.nil?
      step = NumericConstant.new(1)
    else
      steps = @step.evaluate(interpreter)
      step = steps[0]
    end

    @current_value = interpreter.get_value(@control)
    @current_value += step
    interpreter.set_value(@control, @current_value)

    terminated = terminated?(@current_value, step, endv)

    io = interpreter.trace_out
    print_trace_info(io, terminated)

    if terminated
      @current_value = nil
      interpreter.unlock_variable(@control)
      interpreter.exit_fornext
    else
      current_line_index = interpreter.current_line_index
      number = current_line_index.number
      statement_index = current_line_index.statement
      index = current_line_index.index
      for_index = -index
      destination = LineNumberIndex.new(number, statement_index, for_index)
      interpreter.next_line_index = destination
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

  def terminated?(current_value, step, endv)
    zero = NumericConstant.new(0)

    if step > zero
      current_value > endv
    elsif step < zero
      current_value < endv
    else
      false
    end
  end

  def print_trace_info(io, terminated)
    io.trace_output(" terminated:#{terminated}")
  end
end
