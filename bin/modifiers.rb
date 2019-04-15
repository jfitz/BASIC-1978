# IF
class IfModifier
  attr_reader :errors

  def initialize(expression_tokens)
    @errors = []
    @expression = parse_expression(expression_tokens)
  end

  def pretty
    'IF ' + @expression.to_s
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
      expression = ValueScalarExpression.new(expression_tokens)
    rescue BASICExpressionError => e
      @errors << e.message
    end

    expression
  end
end

# FOR
class ForModifier
  attr_reader :errors

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

    @control = VariableName.new(control_tokens[0])
    @start = ValueScalarExpression.new(start_tokens)
    @end = ValueScalarExpression.new(end_tokens)

    if step_tokens.nil?
      @step = nil
    else
      @step = ValueScalarExpression.new(step_tokens)
    end
  end

  def pretty
    if @step.nil?
      "FOR #{@control} = #{@start} TO #{@end}"
    else
      "FOR #{@control} = #{@start} TO #{@end} STEP #{@step}"
    end
  end

  def execute_pre(interpreter)
    start_values = @start.evaluate(interpreter)
    start_value = start_values[0]
    @current_value = start_value if @current_value.nil?
    interpreter.set_value(@control, @current_value)
    end_values = @end.evaluate(interpreter)
    end_value = end_values[0]

    if @step.nil?
      step_value = NumericConstant.new(1)
    else
      step_values = @step.evaluate(interpreter)
      step_value = step_values[0]
    end

    interpreter.lock_variable(@control)
    interpreter.enter_fornext(@control)
    terminated = terminated?(@current_value, step_value, end_value)

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
    end_values = @end.evaluate(interpreter)
    end_value = end_values[0]

    if @step.nil?
      step_value = NumericConstant.new(1)
    else
      step_values = @step.evaluate(interpreter)
      step_value = step_values[0]
    end

    @current_value = interpreter.get_value(@control)
    @current_value += step_value
    interpreter.set_value(@control, @current_value)

    terminated = terminated?(@current_value, step_value, end_value)

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

  def terminated?(current_value, step_value, end_value)
    zero = NumericConstant.new(0)

    if step_value > zero
      current_value > end_value
    elsif step_value < zero
      current_value < end_value
    else
      false
    end
  end

  def print_trace_info(io, terminated)
    io.trace_output(" terminated:#{terminated}")
  end
end
