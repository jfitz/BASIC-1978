# frozen_string_literal: true

# Statement factory class
class StatementFactory
  include Singleton

  attr_writer :tokenbuilders

  def initialize
    @statement_definitions = statement_definitions
    @tokenbuilders = []
  end

  def parse(text)
    line_number = nil
    line = nil
    m = /\A\d+/.match(text)

    unless m.nil?
      token = NumericConstantToken.new(m[0])
      number = IntegerConstant.new(token)
      line_number = LineNumber.new(number)
      line_text = m.post_match
      all_tokens = tokenize(line_text)
      all_tokens.delete_if(&:whitespace?)
      comment = nil

      comment = all_tokens.pop if
        !all_tokens.empty? && all_tokens[-1].comment?

      line = create(line_number, line_text, all_tokens, comment)
    end

    [line_number, line]
  end

  def create(line_number, text, all_tokens, comment)
    statements = []
    statements_tokens = split_on_statement_separators(all_tokens)

    if statements_tokens.empty?
      statement = EmptyStatement.new(line_number)
      statements << statement
    else
      statements_tokens.each do |statement_tokens|
        statement = UnknownStatement.new(line_number, text)

        begin
          statement = create_statement(line_number, text, statement_tokens)
        rescue BASICExpressionError, BASICRuntimeError => e
          statement = InvalidStatement.new(line_number, text, all_tokens, e)
        end

        statements << statement
      end
    end

    Line.new(text, statements, all_tokens, comment)
  end

  def create_statement(line_number, text, statement_tokens)
    statement = EmptyStatement.new(line_number)

    unless statement_tokens.empty?
      statement = nil

      keywords, tokens = extract_keywords(statement_tokens)

      while statement.nil?
        if @statement_definitions.key?(keywords)
          tokens_lists = split_keywords(tokens)

          statement_definition = @statement_definitions[keywords]

          statement =
            statement_definition.new(line_number, keywords, tokens_lists)
        elsif keywords.empty?
          if statement.nil?
            statement = UnknownStatement.new(line_number,
                                             text)
          end
        else
          keyword = keywords.pop
          tokens.unshift(keyword)
        end
      end
    end

    statement
  end

  def keywords_definitions
    keywords = []

    statement_classes.each do |cl|
      kwds = cl.lead_keywords.flatten
      kwds.each { |kwd| keywords << kwd.to_s }

      keywords += cl.extra_keywords
    end

    modifier_classes.each do |cl|
      kwds = cl.lead_keywords.flatten
      kwds.each { |kwd| keywords << kwd.to_s }

      keywords += cl.extra_keywords
    end

    keywords.uniq
  end

  private

  def statement_classes
    [
      ArrForgetStatement,
      ArrInputStatement,
      ArrPlotStatement,
      ArrPrintStatement,
      ArrReadStatement,
      ArrWriteStatement,
      ArrLetStatement,
      ChainStatement,
      CloseStatement,
      DataStatement,
      DefineFunctionStatement,
      DimStatement,
      EndStatement,
      FnendStatement,
      ForgetStatement,
      ForStatement,
      GosubStatement,
      GotoStatement,
      IfStatement,
      InputStatement,
      LetStatement,
      LetLessStatement,
      LineInputStatement,
      MatForgetStatement,
      MatInputStatement,
      MatPlotStatement,
      MatPrintStatement,
      MatReadStatement,
      MatWriteStatement,
      MatLetStatement,
      NextStatement,
      OnStatement,
      OnErrorStatement,
      OpenStatement,
      OptionStatement,
      PrintStatement,
      RandomizeStatement,
      ReadStatement,
      RemarkStatement,
      RestoreStatement,
      ResumeStatement,
      ReturnStatement,
      SleepStatement,
      StopStatement,
      WriteStatement
    ]
  end

  def modifier_classes
    [
      IfModifier,
      UnlessModifier,
      WhileModifier,
      UntilModifier,
      ForToModifier,
      ForToStepModifier,
      ForStepToModifier,
      ForUntilModifier,
      ForUntilStepModifier,
      ForStepUntilModifier,
      ForWhileModifier,
      ForWhileStepModifier,
      ForStepWhileModifier
    ]
  end

  def statement_definitions
    lead_keywords = {}

    statement_classes.each do |class_name|
      keyword_sets = class_name.lead_keywords

      keyword_sets.each do |set|
        lead_keywords[set] = class_name
      end
    end

    lead_keywords
  end

  def split_on_statement_separators(tokens)
    tokens_lists = []
    statement_tokens = []

    tokens.each do |token|
      if token.statement_separator?
        tokens_lists << statement_tokens
        statement_tokens = []
      else
        statement_tokens << token
      end
    end

    tokens_lists << statement_tokens unless statement_tokens.empty?
    tokens_lists
  end

  def extract_keywords(all_tokens)
    keywords = []
    tokens = []
    saw_non_keyword = false

    all_tokens.each do |token|
      saw_non_keyword = true unless token.keyword?
      keywords << token unless saw_non_keyword
      tokens << token if saw_non_keyword
    end

    [keywords, tokens]
  end

  def split_keywords(tokens)
    results = []
    nonkeywords = []

    tokens.each do |token|
      if token.keyword?
        results << nonkeywords unless nonkeywords.empty?
        nonkeywords = []
        results << token
      else
        nonkeywords << token
      end
    end

    results << nonkeywords unless nonkeywords.empty?

    results
  end

  def tokenize(text)
    invalid_tokenbuilder = InvalidTokenBuilder.new
    tokenizer = Tokenizer.new(@tokenbuilders, invalid_tokenbuilder)
    tokenizer.tokenize(text)
  end
end

# parent of all statement classes
class AbstractStatement
  attr_reader :errors, :warnings, :program_errors, :keywords, :tokens,
              :separators, :valid, :executable, :comment, :linenums,
              :autonext, :autonext_line_stmt, :transfers, :transfers_auto,
              :is_if_no_else, :may_be_if_sub, :part_of_sub, :part_of_on_error,
              :part_of_fornext
  attr_accessor :part_of_user_function, :program_warnings, :origins, :reachable

  def self.extra_keywords
    []
  end

  def initialize(_, keywords, tokens_lists)
    @keywords = keywords
    @executable = :run
    @tokens = tokens_lists.flatten
    @core_tokens = tokens_lists.flatten
    @separators = get_separators(@core_tokens)
    @errors = []
    @warnings = []
    @program_errors = []
    @program_warnings = []
    @valid = true
    @comment = false
    @modifiers = []
    @any_if_modifiers = false
    @elements = {
      numerics: [],
      strings: [],
      booleans: [],
      variables: [],
      operators: [],
      functions: [],
      userfuncs: []
    }
    @linenums = []
    @autonext = true
    @comprehension_effort = 1
    @mccabe = 0
    @is_if_no_else = false
    @may_be_if_sub = true
    @profile_count = 0
    @profile_time = 0
    @transfers = []
    @transfers_auto = []
    @part_of_user_function = nil
    @part_of_sub = nil
    @part_of_on_error = nil
    @part_of_fornext = []
  end

  def set_autonext_line_stmt(line_stmt_mod)
    @autonext_line_stmt = line_stmt_mod
  end

  def set_autonext_line(line_stmt_mod)
    @autonext_line = line_stmt_mod
  end

  def pessimize
    @program_errors = []
    @program_warnings = []
  end

  def optimize(interpreter, line_stmt, program)
    set_destinations(interpreter, line_stmt, program)
    set_for_lines(line_stmt, program)
    set_next_lines(line_stmt, program)

    line_number = line_stmt.line_number
    stmt = line_stmt.statement

    @modifiers.each_with_index do |modifier, index|
      mod = index + 1
      mod_line_stmt_mod = LineStmtMod.new(line_number, stmt, mod)
      modifier.optimize(interpreter, mod_line_stmt_mod, program)
    end
  end

  def set_destinations(_, _, _) end

  def assign_sub_markers(_) end

  def assign_sub_marker(marker, line_number, program)
    # mark as part of this sub
    @part_of_sub = marker

    xfers = @transfers + @transfers_auto
    
    # for each destination
    xfers.each do |xfer|
      # don't follow function call and GOSUB
      next if [:function, :gosub].include?(xfer.type)

      dest_line = xfer.line_number
      dest_stmt = xfer.statement
      statement = program.get_statement(dest_line, dest_stmt)

      next if statement.nil?

      if statement.part_of_sub.nil?
        # recurse for that statement's destinations
        statement.assign_sub_marker(marker, dest_line, program)

        # warn about branches to lines before first line of GOSUB block
        if dest_line < marker && dest_line < line_number
          statement.program_warnings << "Statement before GOSUB entry point"
        end
      else
        mark0 = statement.part_of_sub

        if marker != mark0
          # warn about overlapping GOSUB blocks
          statement.program_warnings <<
            "Inconsistent GOSUB target (#{mark0}, #{marker})"
        end
      end
    end
  end

  def assign_on_error_markers(_) end

  def assign_on_error_marker(marker, line_number, program)
    # mark as part of this on-error
    @part_of_on_error = marker

    xfers = @transfers + @transfers_auto
    
    # for each destination
    xfers.each do |xfer|
      # don't follow function call, ON ERROR, and RESUME
      next if [:function, :onerror, :resume].include?(xfer.type)

      dest_line = xfer.line_number
      dest_stmt = xfer.statement
      statement = program.get_statement(dest_line, dest_stmt)

      next if statement.nil?

      if statement.part_of_on_error.nil?
        # recurse for that statement's destinations
        statement.assign_on_error_marker(marker, dest_line, program)

        # warn about branches to lines before first line of ON-ERROR block
        if dest_line < marker && dest_line < line_number
          statement.program_warnings << "Statement before ON-ERROR entry point"
        end
      else
        mark0 = statement.part_of_on_error

        if marker != mark0
          # warn about overlapping ON-ERROR blocks
          statement.program_warnings <<
            "Inconsistent ON-ERROR target (#{mark0}, #{marker})"
        end
      end
    end
  end

  def assign_fornext_markers(_) end

  def assign_fornext_marker(marker, markers, line_number, program)
    # mark as part of this fornext
    @part_of_fornext << marker

    if for?
      markers << @control
    end

    # do not follow if statement is NEXT for this control
    if next?
      # no controls? that's a problem
      return if @controls.empty?

      @controls.each do |control|
        return if markers.size == 1
        
        markers.slice!(-1)
      end
    end

    xfers = @transfers + @transfers_auto
    
    # for each destination
    xfers.each do |xfer|
      # don't follow function call and GOSUB
      next if [:function, :gosub].include?(xfer.type)

      dest_line = xfer.line_number
      dest_stmt = xfer.statement
      statement = program.get_statement(dest_line, dest_stmt)

      next if statement.nil?

      if !statement.part_of_fornext.include?(marker)
        # recurse for that statement's destinations
        statement.assign_fornext_marker(marker, markers, dest_line, program)
      end
    end
  end

  def set_for_lines(_, _) end

  def set_next_lines(_, _) end

  def set_endfunc_lines(_, _) end

  def define_user_functions(_) end

  def load_data(_) end

  def load_file_names(_) end

  def renumber(_) end

  def set_transfers(_)
    @transfers = []
  end

  def set_transfers_auto(program, line_number, stmt)
    @transfers_auto = []

    # convert auto-next to TransferRefLineStmt
    if @autonext && @autonext_line_stmt && (@executable == :run || @origins.size.positive?)
      dest_line_number = @autonext_line_stmt.line_number
      dest_stmt = @autonext_line_stmt.statement

      @transfers_auto <<
        TransferRefLineStmt.new(dest_line_number, dest_stmt, :auto)

      dest_xfer = TransferRefLineStmt.new(line_number, stmt, :auto)
      program.add_statement_origin(dest_line_number, dest_stmt, dest_xfer)
    end
  end

  def transfers_to_origins(program, line_number, stmt)
    xfers = @transfers + @transfers_auto

    xfers.each do |xfer|
      dest_line_number = xfer.line_number
      dest_stmt = xfer.statement
      dest_xfer = TransferRefLineStmt.new(line_number, stmt, xfer.type)
      program.add_statement_origin(dest_line_number, dest_stmt, dest_xfer)
    end
  end

  def uncache
    uncache_core

    @modifiers.each(&:uncache)
  end

  def uncache_core; end

  def reset_profile_metrics
    @profile_count = 0
    @profile_time = 0

    @modifiers.each(&:reset_profile_metrics)
  end

  def pretty
    AbstractToken.pretty_tokens(@keywords, @tokens)
  end

  def core_pretty
    AbstractToken.pretty_tokens(@keywords, @core_tokens)
  end

  def analyze_pretty(number)
    texts = []

    text = ''

    text += "#{@part_of_user_function} " unless @part_of_user_function.nil?
    text += "E(#{@part_of_on_error}) " unless @part_of_on_error.nil?
    text += "G(#{@part_of_sub}) " unless @part_of_sub.nil?
    text += "F(#{@part_of_fornext.map(&:to_s).join(',')}) " unless @part_of_fornext.empty?
    text += "(#{@mccabe} #{@comprehension_effort}) #{number} #{core_pretty}"

    texts << text

    number = ' ' * number.size

    @modifiers.each do |modifier|
      texts << modifier.pre_analyze(number)
      texts << modifier.post_analyze(number)
    end

    texts
  end

  def comprehension_effort
    result = @comprehension_effort

    @modifiers.each do |modifier|
      result += modifier.pre_comp_effort + modifier.post_comp_effort
    end

    result
  end

  def mccabe
    result = @mccabe
    @modifiers.each { |modifier| result += modifier.mccabe }
    result
  end

  def pre_trace(mod)
    mod = -mod
    mod -= 1
    @modifiers[mod].pre_trace
  end

  def core_trace
    AbstractToken.pretty_tokens(@keywords, @core_tokens)
  end

  def post_trace(mod)
    mod -= 1
    @modifiers[mod].post_trace
  end

  def dump
    ['Unimplemented']
  end

  def numerics
    @elements[:numerics]
  end

  def strings
    @elements[:strings]
  end

  def booleans
    @elements[:booleans]
  end

  def variables
    @elements[:variables]
  end

  def operators
    @elements[:operators]
  end

  def functions
    @elements[:functions]
  end

  def userfuncs
    @elements[:userfuncs]
  end

  def modifier_numerics
    nums = []
    @modifiers.each { |modifier| nums += modifier.numerics }
    nums
  end

  def numeric_constants
    syms = @tokens.clone
    syms.keep_if(&:numeric_constant?)
  end

  def modifier_strings
    strs = []
    @modifiers.each { |modifier| strs += modifier.strings }
    strs
  end

  def modifier_booleans
    bools = []
    @modifiers.each { |modifier| bools += modifier.booleans }
    bools
  end

  def text_constants
    syms = @tokens.clone
    syms.keep_if(&:text_constant?)
  end

  def modifier_variables
    vars = []
    @modifiers.each { |modifier| vars += modifier.variables }
    vars
  end

  def modifier_operators
    opers = []
    @modifiers.each { |modifier| opers += modifier.operators }
    opers
  end

  def modifier_functions
    vars = []
    @modifiers.each { |modifier| vars += modifier.functions }
    vars
  end

  def modifier_userfuncs
    vars = []
    @modifiers.each { |modifier| vars += modifier.userfuncs }
    vars
  end

  def for?
    @keywords.size == 1 && @keywords[0].to_s == 'FOR'
  end

  def next?
    @keywords.size == 1 && @keywords[0].to_s == 'NEXT'
  end

  def procedure?
    is_proc = false

    # a procedure start is any line with a :gosub origin
    @origins.each do |xfer|
      is_proc = true if !xfer.line_number.nil? && xfer.type == :gosub
    end

    is_proc
  end

  def print_errors(console_io)
    @errors.each { |error| console_io.print_line(" #{error}") }
  end

  def errors?
    !@errors.empty? || !@program_errors.empty?
  end

  def check_gosub_origins(_, _)
    # check all origins are consistent for GOSUB
    any_gosub = false
    any_other = false
    @origins.each do |origin|
      any_gosub = true if origin.type == :gosub
      any_other = true if origin.type != :gosub
    end
    @program_warnings << 'Inconsistent GOSUB origins' if any_gosub && any_other
  end

  def check_onerror_origins(_, _)
    # check all origins are consistent for ON ERROR
    any_on_error = false
    any_other = false
    @origins.each do |origin|
      any_on_error = true if origin.type == :onerror
      any_other = true if origin.type != :onerror
    end
    @program_warnings << 'Inconsistent ON-ERROR origins' if any_on_error && any_other
  end

  def check_terminating_in_gosub
    return if @part_of_sub.nil?

    xfers = @transfers + @transfers_auto

    # warn about STOP, END, CHAIN in GOSUB block
    xfers.each do |xfer|
      if [:stop, :chain].include?(xfer.type)
        @program_warnings << "Terminating statement in GOSUB"
      end
    end
  end

  def check_terminating_in_onerror
    return if @part_of_onerror.nil?

    xfers = @transfers + @transfers_auto

    # warn about STOP, END, CHAIN in GOSUB block
    xfers.each do |xfer|
      if [:stop, :chain].include?(xfer.type)
        @program_warnings << "Terminating statement in ON-ERROR"
      end
    end
  end

  def check_terminating_in_fornext
    return if @part_of_fornext.empty?

    xfers = @transfers + @transfers_auto

    # warn about STOP, END, CHAIN in GOSUB block
    xfers.each do |xfer|
      if [:stop, :chain].include?(xfer.type)
        @program_warnings << "Terminating statement in FOR/NEXT"
      end
    end
  end

  def check_program(_, _)
  end

  def number_for_stmts
    0
  end

  def profile(show_timing)
    # core statement
    text = AbstractToken.pretty_tokens(@keywords, @core_tokens)
    text = " #{text}" unless text.empty?

    line = ' '

    line += "#{@part_of_user_function} " unless @part_of_user_function.nil?
    line += "E(#{@part_of_on_error}) " unless @part_of_on_error.nil?
    line += "G(#{@part_of_sub}) " unless @part_of_sub.nil?
    line += "F(#{@part_of_fornext.map(&:to_s).join(',')}) " unless @part_of_fornext.empty?

    line += if show_timing
              "(#{@profile_time.round(4)}/#{@profile_count})"
            else
              "(#{@profile_count})"
            end

    line += text

    lines = [line]

    # modifiers
    @modifiers.each do |modifier|
      # first the pre line
      text = modifier.pre_pretty

      if show_timing
        timing = modifier.profile_pre_time.round(3).to_s
        line = " (#{timing}/#{modifier.profile_pre_count})#{text}"
      else
        line = " (#{modifier.profile_pre_count})#{text}"
      end
      lines << line

      # then the post line
      text = modifier.post_pretty

      if show_timing
        timing = modifier.profile_post_time.round(3).to_s
        line = " (#{timing}/#{modifier.profile_post_count})#{text}"
      else
        line = " (#{modifier.profile_post_count})#{text}"
      end
      lines << line
    end

    lines
  end

  def print_trace_info(trace_out, current_line_stmt_mod)
    trace_out.newline_when_needed

    trace_out.print_out "#{@part_of_user_function} " unless
      @part_of_user_function.nil?

    trace_out.print_out "E(#{@part_of_on_error}) " unless @part_of_on_error.nil?
    trace_out.print_out "G(#{@part_of_sub}) " unless @part_of_sub.nil?
    trace_out.print_out "F(#{@part_of_fornext.map(&:to_s).join(',')}) " unless @part_of_fornext.empty?

    mod = current_line_stmt_mod.index

    text = ''

    text = pre_trace(mod) if mod.negative?
    text = core_trace if mod.zero?
    text = post_trace(mod) if mod.positive?

    text = " #{text}" unless text.empty?
    text = "#{current_line_stmt_mod}:#{text}"

    trace_out.print_out(text)
    trace_out.newline
  end

  def execute_a_statement(interpreter, _current_line_stmt_mod)
    current_user_function = interpreter.current_user_function

    if @part_of_user_function != current_user_function
      raise(BASICSyntaxError, 'Invalid transfer in/out of function')
    end

    # TODO: check for consistent SUB

    execute(interpreter)
  end

  def start_index
    0 - @modifiers.size
  end

  def last_index
    @modifiers.size
  end

  def singledef?
    false
  end

  def multidef?
    false
  end

  def multiend?
    false
  end

  protected

  def check_template(tokens_lists, template)
    return false unless tokens_lists.size == template.size

    result = true
    pairs = template.zip(tokens_lists)

    pairs.each do |pair|
      control = pair[0]
      value = pair[1]

      if control.class.to_s == 'Array' &&
         value.class.to_s == 'Array'

        # control array and value array implies an expression
        result &= value.size == control[0] if control.size == 1

        result &= value.size >= control[0] if
          control.size == 2 && control[1] == '>='

      elsif control.class.to_s == 'Array' &&
            value.class.to_s == 'KeywordToken'

        # control array and single value (not array of one) implies
        # multiple possible keywords
        result &= control.include?(value.to_s)

      elsif control.class.to_s == 'String' &&
            value.class.to_s == 'KeywordToken'

        # single control and single value is a specific keyword
        result &= value.to_s == control

      else
        result = false
      end
    end

    result
  end

  def split_tokens(tokens, want_separators)
    lists = []
    list = []
    parens_level = 0

    tokens.each do |token|
      if token.operand? &&
         (!list.empty? && (list[-1].operand? || list[-1].group_end?))
        lists << list unless list.empty?
        list = [token]
      elsif token.separator? && parens_level.zero?
        lists << list unless list.empty?
        lists << token if want_separators
        list = []
      else
        list << token
      end

      parens_level += 1 if token.group_start?
      parens_level -= 1 if token.group_end? && !parens_level.zero?
    end

    lists << list unless list.empty?

    lists
  end

  def split_on_token(tokens, token_to_split)
    results = []
    list = []

    tokens.each do |token|
      if token.to_s == token_to_split
        results << list unless list.empty?
        list = []
        results << token
      else
        list << token
      end
    end

    results << list unless list.empty?

    results
  end

  def split_keywords(tokens)
    results = []
    nonkeywords = []

    tokens.each do |token|
      if token.keyword?
        results << nonkeywords unless nonkeywords.empty?
        nonkeywords = []
        results << token
      else
        nonkeywords << token
      end
    end

    results << nonkeywords unless nonkeywords.empty?

    results
  end

  def split_on_group_separators(tokens)
    tokens_lists = []
    statement_tokens = []

    # set to TRUE, so an empty list creates one empty token
    last_was_separator = true

    tokens.each do |token|
      if token.separator?
        tokens_lists << statement_tokens
        statement_tokens = []
        last_was_separator = true
      else
        statement_tokens << token
        last_was_separator = false
      end
    end

    tokens_lists << statement_tokens if
      !statement_tokens.empty? || last_was_separator
    tokens_lists
  end

  def make_references(items, exp1 = nil, exp2 = nil)
    numerics = []
    strings = []
    booleans = []
    variables = []
    operators = []
    functions = []
    userfuncs = []

    unless exp1.nil?
      numerics += exp1.numerics
      strings += exp1.strings
      booleans += exp1.booleans
      variables += exp1.variables
      operators += exp1.operators
      functions += exp1.functions
      userfuncs += exp1.userfuncs
    end

    unless exp2.nil?
      numerics += exp2.numerics
      strings += exp2.strings
      booleans += exp2.booleans
      variables += exp2.variables
      operators += exp2.operators
      functions += exp2.functions
      userfuncs += exp2.userfuncs
    end

    unless items.nil?
      items.each { |item| numerics += item.numerics }
      items.each { |item| strings += item.strings }
      items.each { |item| booleans += item.booleans }
      items.each { |item| variables += item.variables }
      items.each { |item| operators += item.operators }
      items.each { |item| functions += item.functions }
      items.each { |item| userfuncs += item.userfuncs }
    end

    {
      numerics: numerics,
      strings: strings,
      booleans: booleans,
      variables: variables,
      operators: operators,
      functions: functions,
      userfuncs: userfuncs
    }
  end

  private

  def make_modifier(tokens_lists)
    template_if = ['IF', [1, '>=']]

    if tokens_lists.size > 1 &&
       check_template(tokens_lists.last(2), template_if)

      # create the modifier
      modifier_tokens = tokens_lists.last(2)
      modifier = IfModifier.new(modifier_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(2)

      @any_if_modifiers = true

      return true
    end

    template_unless = ['UNLESS', [1, '>=']]

    if tokens_lists.size > 1 &&
       check_template(tokens_lists.last(2), template_unless)

      # create the modifier
      modifier_tokens = tokens_lists.last(2)
      modifier = UnlessModifier.new(modifier_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(2)

      # any_if because its a conditional
      @any_if_modifiers = true

      return true
    end

    template_for_to = ['FOR', [1, '>='], 'TO', [1, '>=']]
    template_for_to_step = ['FOR', [1, '>='], 'TO', [1, '='], 'STEP', [1, '>=']]
    template_for_step_to = ['FOR', [1, '>='], 'STEP', [1, '>='], 'TO', [1, '=']]
    template_for_until = ['FOR', [1, '>='], 'UNTIL', [1, '>=']]
    template_for_until_step = ['FOR', [1, '>='], 'UNTIL', [1, '>='], 'STEP',
                               [1, '>=']]
    template_for_step_until = ['FOR', [1, '>='], 'STEP', [1, '>='], 'UNTIL',
                               [1, '>=']]
    template_for_while = ['FOR', [1, '>='], 'WHILE', [1, '>=']]
    template_for_while_step = ['FOR', [1, '>='], 'WHILE', [1, '>='], 'STEP',
                               [1, '>=']]
    template_for_step_while = ['FOR', [1, '>='], 'STEP', [1, '>='], 'WHILE',
                               [1, '>=']]

    if tokens_lists.size > 4 &&
       check_template(tokens_lists.last(4), template_for_to)

      # create the modifier
      expression_tokens = tokens_lists.last(4)
      control_and_start_tokens = tokens_lists[-3]
      end_tokens = tokens_lists.last

      modifier = ForToModifier.new(expression_tokens, control_and_start_tokens,
                                   end_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(4)

      return true
    end

    if tokens_lists.size > 6 &&
       check_template(tokens_lists.last(6), template_for_to_step)

      # create the modifier
      expression_tokens = tokens_lists.last(6)
      control_and_start_tokens = tokens_lists[-5]
      end_tokens = tokens_lists[-3]
      step_tokens = tokens_lists.last

      modifier =
        ForToStepModifier.new(expression_tokens, control_and_start_tokens,
                              step_tokens, end_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(6)

      return true
    end

    if tokens_lists.size > 6 &&
       check_template(tokens_lists.last(6), template_for_step_to)

      # create the modifier
      expression_tokens = tokens_lists.last(6)
      control_and_start_tokens = tokens_lists[-5]
      end_tokens = tokens_lists.last
      step_tokens = tokens_lists[-3]

      modifier =
        ForStepToModifier.new(expression_tokens, control_and_start_tokens,
                              step_tokens, end_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(6)

      return true
    end

    if tokens_lists.size > 4 &&
       check_template(tokens_lists.last(4), template_for_until)

      # create the modifier
      expression_tokens = tokens_lists.last(4)
      control_and_start_tokens = tokens_lists[-3]
      until_tokens = tokens_lists.last

      modifier = ForUntilModifier.new(expression_tokens,
                                      control_and_start_tokens, until_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(4)

      return true
    end

    if tokens_lists.size > 6 &&
       check_template(tokens_lists.last(6), template_for_until_step)

      # create the modifier
      expression_tokens = tokens_lists.last(6)
      control_and_start_tokens = tokens_lists[-5]
      until_tokens = tokens_lists[-3]
      step_tokens = tokens_lists.last

      modifier =
        ForUntilStepModifier.new(expression_tokens, control_and_start_tokens,
                                 step_tokens, until_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(6)

      return true
    end

    if tokens_lists.size > 6 &&
       check_template(tokens_lists.last(6), template_for_step_until)

      # create the modifier
      expression_tokens = tokens_lists.last(6)
      control_and_start_tokens = tokens_lists[-5]
      until_tokens = tokens_lists.last
      step_tokens = tokens_lists[-3]

      modifier =
        ForStepUntilModifier.new(expression_tokens, control_and_start_tokens,
                                 step_tokens, until_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(6)

      return true
    end

    if tokens_lists.size > 4 &&
       check_template(tokens_lists.last(4), template_for_while)

      # create the modifier
      expression_tokens = tokens_lists.last(4)
      control_and_start_tokens = tokens_lists[-3]
      while_tokens = tokens_lists.last

      modifier = ForWhileModifier.new(expression_tokens,
                                      control_and_start_tokens, while_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(4)

      return true
    end

    if tokens_lists.size > 6 &&
       check_template(tokens_lists.last(6), template_for_while_step)

      # create the modifier
      expression_tokens = tokens_lists.last(6)
      control_and_start_tokens = tokens_lists[-5]
      while_tokens = tokens_lists[-3]
      step_tokens = tokens_lists.last

      modifier =
        ForWhileStepModifier.new(expression_tokens, control_and_start_tokens,
                                 step_tokens, while_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(6)

      return true
    end

    if tokens_lists.size > 6 &&
       check_template(tokens_lists.last(6), template_for_step_while)

      # create the modifier
      expression_tokens = tokens_lists.last(6)
      control_and_start_tokens = tokens_lists[-5]
      while_tokens = tokens_lists.last
      step_tokens = tokens_lists[-3]

      modifier =
        ForStepWhileModifier.new(expression_tokens, control_and_start_tokens,
                                 step_tokens, while_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(6)

      return true
    end

    # WHILE modifier must follow FOR-WHILE
    template_unless = ['WHILE', [1, '>=']]

    if tokens_lists.size > 1 &&
       check_template(tokens_lists.last(2), template_unless)

      # create the modifier
      modifier_tokens = tokens_lists.last(2)
      modifier = WhileModifier.new(modifier_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(2)

      # any_if because its a conditional
      @any_if_modifiers = true

      return true
    end

    # UNTIL modifier must follow FOR-UNTIL
    template_unless = ['UNTIL', [1, '>=']]

    if tokens_lists.size > 1 &&
       check_template(tokens_lists.last(2), template_unless)

      # create the modifier
      modifier_tokens = tokens_lists.last(2)
      modifier = UntilModifier.new(modifier_tokens)
      @modifiers.unshift(modifier)

      # remove the tokens used for the modifier
      tokens_lists.pop(2)

      # any_if because its a conditional
      @any_if_modifiers = true

      return true
    end

    false
  end

  def execute_premodifier(interpreter)
    current_line_stmt_mod = interpreter.current_line_stmt_mod
    mod = 0 - (current_line_stmt_mod.index + 1)
    modifier = @modifiers[mod]
    modifier.execute_pre(interpreter)
  end

  def execute_postmodifier(interpreter)
    current_line_stmt_mod = interpreter.current_line_stmt_mod
    mod = current_line_stmt_mod.index - 1
    modifier = @modifiers[mod]
    modifier.execute_post(interpreter)
  end

  def extract_modifiers(tokens_lists)
    while make_modifier(tokens_lists); end
    @core_tokens = tokens_lists.flatten

    @modifiers.each do |modifier|
      @errors += modifier.errors
      @warnings += modifier.warnings
    end
  end

  def execute(interpreter)
    current_line_stmt_mod = interpreter.current_line_stmt_mod
    mod = current_line_stmt_mod.index

    execute_premodifier(interpreter) if mod.negative?

    if mod.zero?
      timing = Benchmark.measure { execute_core(interpreter) }

      user_time = timing.utime + timing.cutime
      sys_time = timing.stime + timing.cstime
      time = user_time + sys_time

      @profile_time += time
      @profile_count += 1
    end

    execute_postmodifier(interpreter) if mod.positive?
  end

  def get_separators(tokens)
    wanted = ['(', ')', '[', ']', ',', ';']

    separators = []

    tokens.each do |token|
      separators << token if wanted.include?(token.to_s)
    end

    separators
  end
end

# unparsed statement
class InvalidStatement < AbstractStatement
  def initialize(line_number, text, all_tokens, error)
    super(line_number, [], all_tokens)

    @valid = false
    @executable = :none
    @autonext = false
    @text = text
    @errors << ("Invalid statement: #{error.message}")
  end

  def to_s
    @text
  end

  def execute_core(_)
    raise(BASICSyntaxError, @errors[0])
  end
end

# unknown statement
class UnknownStatement < AbstractStatement
  def initialize(line_number, text)
    super(line_number, [], [])

    @valid = false
    @executable = :none
    @text = text
    @errors << "Unknown statement '#{text.strip}'"
  end

  def to_s
    @text
  end

  def execute_core(_) end
end

# empty statement (line number only)
class EmptyStatement < AbstractStatement
  def initialize(line_number)
    super(line_number, [], [])

    @valid = false
    @executable = :none

    @comprehension_effort = 0
  end

  def dump
    []
  end

  def to_s
    ''
  end

  def execute_core(_) end
end

# REMARK
class RemarkStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('REMARK')],
      [KeywordToken.new('REM')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    @valid = false
    @comment = true
    @executable = :none
    @rest = Remark.new(nil)
    @rest = Remark.new(tokens_lists[0]) unless tokens_lists.empty?
  end

  def dump
    lines = [@rest.dump]

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(_) end
end

# common functions for IO statements
module FileFunctions
  def extract_file_handle(items)
    file_tokens = nil

    unless items.empty? ||
           items[0].carriage_control?

      candidate_file_tokens = items[0]

      if candidate_file_tokens.filehandle?
        file_tokens = items.shift

        items.shift if
          !items.empty? &&
          items[0].carriage_control?
      end
    end

    file_tokens
  end

  def get_file_handle(interpreter, file_tokens)
    return nil if file_tokens.nil?

    file_handles = file_tokens.evaluate(interpreter)
    file_handles[0]
  end

  def add_needed_value(items, shape)
    items << ValueExpressionSet.new([], shape) if
      items.empty? || items[-1].carriage_control?
  end

  def add_needed_carriage(items)
    items << CarriageControl.new('') if
      !items.empty? && !items[-1].carriage_control?
  end

  def add_final_carriage(items, final)
    items << final if
      !items.empty? && !items[-1].carriage_control?
  end

  def add_default_value_carriage(items, shape)
    return unless items.empty?

    add_needed_value(items, shape)
    add_final_carriage(items, CarriageControl.new('NL'))
  end

  def dump
    lines = []

    lines += @file_tokens.dump unless @file_tokens.nil?
    @items&.each { |item| lines += item.dump }

    @modifiers&.each { |item| lines += item.dump }

    lines
  end
end

# common functions for INPUT statements
module InputFunctions
  def extract_prompt(items)
    prompt = nil

    unless items.empty? ||
           items[0].carriage_control?

      candidate_prompt_tokens = items[0]

      if candidate_prompt_tokens.text_constant?
        prompt = items.shift

        items.shift if
          !items.empty? &&
          items[0].carriage_control?
      end
    end

    prompt
  end

  def tokens_to_expressions(tokens_lists, shape, set_dims)
    items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(items, tokens_list, shape, set_dims)
      end
    end

    items
  end

  def add_expression(items, tokens, shape, set_dims)
    items << if tokens[0].operator? && tokens[0].pound?
               ValueExpressionSet.new(tokens, :scalar)
             elsif tokens[0].text_constant?
               ValueExpressionSet.new(tokens, :scalar)
             else
               TargetExpressionSet.new(tokens, shape, set_dims)
             end
  rescue BASICExpressionError => e
    line_text = tokens.map(&:to_s).join
    @errors << ("Syntax error: \"#{line_text}\" #{e}")
  end

  def zip(names, values)
    raise BASICRuntimeError, :te_too_few if values.size < names.size

    results = []
    (0...names.size).each do |i|
      results << { 'name' => names[i], 'value' => values[i] }
    end

    results
  end

  def input_values(fhr, interpreter, prompt, count)
    values = []

    while values.size < count
      remaining = count - values.size
      fhr.prompt(prompt, remaining)
      values += fhr.input(interpreter)

      prompt = nil
    end

    values
  end

  def file_values(fhr, interpreter)
    values = []

    values += fhr.input(interpreter)

    values
  end

  def uncache_core
    @items.each(&:uncache)
  end
end

# common functions for PRINT statements
module PrintFunctions
  def tokens_to_expressions(tokens_lists, shape)
    items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(items, tokens_list, shape)
      elsif tokens_list.separator?
        add_needed_value(items, shape)
        items << CarriageControl.new(tokens_list.to_s)
      end
    end

    add_final_carriage(items, CarriageControl.new('NL'))
    add_default_value_carriage(items, shape)
    items
  end

  def tokens_to_expressions_2(tokens_lists, shape)
    items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(items, tokens_list, shape)
      end
    end

    items
  end

  def add_expression(items, tokens, shape)
    if tokens[0].operator? && tokens[0].pound?
      items << ValueExpressionSet.new(tokens, :scalar)
    else
      add_needed_carriage(items)
      items << ValueExpressionSet.new(tokens, shape)
    end
  rescue BASICExpressionError => e
    line_text = tokens.map(&:to_s).join
    @errors << ("Syntax error: \"#{line_text}\" #{e}")
  end

  def extract_format(items, interpreter)
    items = items.clone
    format = nil

    unless items.empty? ||
           (items[0].class.to_s != 'ValueExpressionSet' &&
           items[-1].scalar?)

      value = first_item(items, interpreter)

      if value.text_constant?
        format = value
        items.shift

        items.shift if
          !items.empty? &&
          items[0].carriage_control?
      end
    end

    [format, items]
  end

  def first_item(items, interpreter)
    first_list = items[0]
    values = first_list.evaluate(interpreter)

    values[0]
  end

  def split_format(format)
    format_text = format.to_v
    tokenbuilders = [
      ConstantFormatTokenBuilder.new,
      PaddedStringFormatTokenBuilder.new,
      PlainStringFormatTokenBuilder.new,
      CharFormatTokenBuilder.new,
      NumericFormatTokenBuilder.new
    ]
    tokenizer = Tokenizer.new(tokenbuilders, nil)
    tokenizer.tokenize(format_text)
  end

  def dump
    lines = []

    lines += @file_tokens.dump unless @file_tokens.nil?

    @items.each do |item|
      if item.class.to_s == 'Array'
        item.each { |it| lines += it.dump }
      elsif item.keyword?
        lines << ("Keyword:#{item}")
      end
    end

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def uncache_core
    @items.each do |item|
      item.each(&:uncache) if item.class.to_s == 'Array'
    end
  end
end

# common functions for READ statements
module ReadFunctions
  def tokens_to_expressions(tokens_lists, shape, set_dims)
    items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(items, tokens_list, shape, set_dims)
      end
    end

    items
  end

  def add_expression(items, tokens, shape, set_dims)
    items << if tokens[0].operator? && tokens[0].pound?
               ValueExpressionSet.new(tokens, :scalar)
             else
               TargetExpressionSet.new(tokens, shape, set_dims)
             end
  rescue BASICExpressionError => e
    line_text = tokens.map(&:to_s).join
    @errors << ("Syntax error: \"#{line_text}\" #{e}")
  end

  def uncache_core
    @items.each(&:uncache)
  end
end

# common functions for WRITE statements
module WriteFunctions
  def tokens_to_expressions(tokens_lists, shape)
    items = []

    tokens_lists.each do |tokens_list|
      if tokens_list.class.to_s == 'Array'
        add_expression(items, tokens_list, shape)
      elsif tokens_list.separator?
        add_needed_value(items, shape)
        items << CarriageControl.new(tokens_list.to_s)
      end
    end

    add_final_carriage(items, CarriageControl.new('NL'))
    add_default_value_carriage(items, shape)
    items
  end

  def add_expression(items, tokens, shape)
    if tokens[0].operator? && tokens[0].pound?
      items << ValueExpressionSet.new(tokens, :scalar)
    else
      add_needed_carriage(items)
      items << ValueExpressionSet.new(tokens, shape)
    end
  rescue BASICExpressionError => e
    line_text = tokens.map(&:to_s).join
    @errors << ("Syntax error: \"#{line_text}\" #{e}")
  end

  def uncache_core
    @items.each(&:uncache)
  end
end

# CHAIN
class ChainStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('CHAIN')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)
    @autonext = false unless @any_if_modifiers

    template = [[1, '>']]

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)

    target_tokens = tokens_lists[0]
    @target = ValueExpressionSet.new(target_tokens, :scalar)
    @errors << 'TAB() not allowed' if @target.has_tab

    @elements = make_references(nil, @target)

    @comprehension_effort += @target.comprehension_effort
  end

  def set_transfers(_)
    @transfers = []

    empty_line_number = LineNumber.new(nil)
    @transfers << TransferRefLineStmt.new(empty_line_number, 0, :chain)
  end

  def uncache_core
    @target.uncache
  end

  def dump
    lines = ['']

    lines += @target.dump

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    target_values = @target.evaluate(interpreter)
    target_value = target_values[0]

    raise(BASICExpressionError, 'Target must be text item.') unless
      target_value.text_constant?

    interpreter.chain(target_values)
  end
end

# CLOSE
class CloseStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('CLOSE')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]
    template_file = ['FILE', [1, '>=']]

    @filenum_expression = []
    if check_template(tokens_lists, template) ||
       check_template(tokens_lists, template_file)
      @filenum_expression = ValueExpressionSet.new(tokens_lists[-1], :scalar)
      @errors << 'TAB() not allowed' if @filenum_expression.has_tab

      @elements = make_references(nil, @filenum_expression)

      @comprehension_effort += @filenum_expression.comprehension_effort
    else
      @errors << 'Syntax error'
    end
  end

  def uncache_core
    @filenum_expression.uncache
  end

  def dump
    lines = @filenum_expression.dump

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    fns = @filenum_expression.evaluate(interpreter)
    fh = FileHandle.new(fns[0])
    interpreter.close_file(fh)
  end
end

# DATA
class DataStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('DATA')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    @executable = :load_data
    @may_be_if_sub = false

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      @expressions = ValueExpressionSet.new(tokens_lists[0], :scalar)
      @errors << 'TAB() not allowed' if @expressions.has_tab

      @elements = make_references(nil, @expressions)

      @comprehension_effort += @expressions.comprehension_effort
    else
      @errors << 'Syntax error'
    end
  end

  def uncache_core
    @expressions&.uncache
  end

  def dump
    lines = []

    lines += @expressions.dump unless @expressions.nil?

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def load_data(interpreter)
    ds = interpreter.get_data_store(nil)
    data_list = @expressions.evaluate(interpreter)
    ds.store(data_list)
  rescue BASICRuntimeError => e
    @errors << e.message
  end

  def execute_core(_) end
end

# DEF FNx
class DefineFunctionStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('DEF')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    @executable = :def_fn
    @may_be_if_sub = false
    @autonext = false

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      begin
        @definition = UserFunctionDefinition.new(tokens_lists[0])
        @autonext = @definition.multidef?

        @elements = make_references(nil, @definition)

        @comprehension_effort += @definition.comprehension_effort
      rescue BASICExpressionError => e
        @errors << e.message
      end
    else
      @errors << 'Syntax error'
    end
  end

  def set_endfunc_lines(line_stmt, program)
    return unless multidef?

    name = @definition.name

    begin
      @endfunc_line_stmt =
        program.find_closing_endfunc_line_stmt(name, line_stmt)
    rescue BASICSyntaxError => e
      @program_errors << e.message
    end
  end

  def define_user_functions(interpreter)
    unless @definition.nil?
      begin
        interpreter.set_user_function(@definition)
      rescue BASICRuntimeError => e
        @program_errors << e.message
      end
    end
  end

  def singledef?
    return false if @definition.nil?

    @definition.singledef?
  end

  def multidef?
    return false if @definition.nil?

    @definition.multidef?
  end

  def function_name
    @definition.name
  end

  def function_signature
    @definition.signature
  end

  def dump
    lines = []

    lines += @definition.dump unless @definition.nil?

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(_) end
end

# DIM
class DimStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('DIM')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    template = [[1, '>=']]

    @declarations = []
    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], false)

      tokens_lists.each do |tokens_list|
        @declarations << DeclarationExpressionSet.new(tokens_list)
      rescue BASICExpressionError => e
        @errors << ("Invalid #{tokens_list.map(&:to_s).join} #{e}")
      end

      @elements = make_references(@declarations)

      @declarations.each do |expression|
        @comprehension_effort += expression.comprehension_effort
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []

    @declarations.each { |expression| lines += expression.dump }

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    @declarations.each do |expression|
      variables = expression.evaluate(interpreter)
      variable = variables[0]
      subscripts = variable.subscripts

      if subscripts.empty?
        raise BASICSyntaxError, 'DIM statement requires subscript range'
      end

      interpreter.set_dimensions(variable, subscripts)
    end
  end
end

# END
class EndStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('END')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    @autonext = false
    @may_be_if_sub = false

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def set_transfers(_)
    @transfers = []

    empty_line_number = LineNumber.new(nil)
    @transfers << TransferRefLineStmt.new(empty_line_number, 0, :stop)
  end

  def check_program(program, line_number_stmt)
    next_line_stmt = program.find_next_line_stmt(line_number_stmt)

    @program_errors << 'Statements after END' unless next_line_stmt.nil?
  end

  def dump
    lines = ['']

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    io = interpreter.console_io
    io.newline_when_needed
    interpreter.stop
  end
end

# FNEND
class FnendStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('FNEND')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    @may_be_if_sub = false
    @autonext = false

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def multiend?
    true
  end

  def dump
    lines = ['']

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    interpreter.exit_user_function
  end
end

# FOR statement
class ForStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('FOR')]
    ]
  end

  def self.extra_keywords
    %w[TO STEP UNTIL WHILE]
  end

  def initialize(_, keywords, tokens_lists)
    super

    @autonext = false
    @may_be_if_sub = $options['if_for_sub'].value

    template_to = [[1, '>='], 'TO', [1, '>=']]
    template_to_step = [[1, '>='], 'TO', [1, '>='], 'STEP', [1, '>=']]
    template_step_to = [[1, '>='], 'STEP', [1, '>='], 'TO', [1, '>=']]
    template_until = [[1, '>='], 'UNTIL', [1, '>=']]
    template_until_step = [[1, '>='], 'UNTIL', [1, '>='], 'STEP', [1, '>=']]
    template_step_until = [[1, '>='], 'STEP', [1, '>='], 'UNTIL', [1, '>=']]
    template_while = [[1, '>='], 'WHILE', [1, '>=']]
    template_while_step = [[1, '>='], 'WHILE', [1, '>='], 'STEP', [1, '>=']]
    template_step_while = [[1, '>='], 'STEP', [1, '>='], 'WHILE', [1, '>=']]

    if check_template(tokens_lists, template_to)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        variable_name = VariableName.new(tokens1[0])
        @control = Variable.new(variable_name, :scalar, [], [])
        @start = ValueExpressionSet.new(tokens2, :scalar)
        @step = nil
        @end = ValueExpressionSet.new(tokens_lists[2], :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end
    elsif check_template(tokens_lists, template_to_step)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        variable_name = VariableName.new(tokens1[0])
        @control = Variable.new(variable_name, :scalar, [], [])
        @start = ValueExpressionSet.new(tokens2, :scalar)
        @step = ValueExpressionSet.new(tokens_lists[4], :scalar)
        @end = ValueExpressionSet.new(tokens_lists[2], :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end
    elsif check_template(tokens_lists, template_step_to)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        variable_name = VariableName.new(tokens1[0])
        @control = Variable.new(variable_name, :scalar, [], [])
        @start = ValueExpressionSet.new(tokens2, :scalar)
        @step = ValueExpressionSet.new(tokens_lists[2], :scalar)
        @end = ValueExpressionSet.new(tokens_lists[4], :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end
    elsif check_template(tokens_lists, template_until)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        variable_name = VariableName.new(tokens1[0])
        @control = Variable.new(variable_name, :scalar, [], [])
        @start = ValueExpressionSet.new(tokens2, :scalar)
        @until = ValueExpressionSet.new(tokens_lists[2], :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end
    elsif check_template(tokens_lists, template_until_step)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        variable_name = VariableName.new(tokens1[0])
        @control = Variable.new(variable_name, :scalar, [], [])
        @start = ValueExpressionSet.new(tokens2, :scalar)
        @until = ValueExpressionSet.new(tokens_lists[2], :scalar)
        @step = ValueExpressionSet.new(tokens_lists[4], :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end
    elsif check_template(tokens_lists, template_step_until)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        variable_name = VariableName.new(tokens1[0])
        @control = Variable.new(variable_name, :scalar, [], [])
        @start = ValueExpressionSet.new(tokens2, :scalar)
        @step = ValueExpressionSet.new(tokens_lists[2], :scalar)
        @until = ValueExpressionSet.new(tokens_lists[4], :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end
    elsif check_template(tokens_lists, template_while)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        variable_name = VariableName.new(tokens1[0])
        @control = Variable.new(variable_name, :scalar, [], [])
        @start = ValueExpressionSet.new(tokens2, :scalar)
        @while = ValueExpressionSet.new(tokens_lists[2], :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end
    elsif check_template(tokens_lists, template_while_step)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        variable_name = VariableName.new(tokens1[0])
        @control = Variable.new(variable_name, :scalar, [], [])
        @start = ValueExpressionSet.new(tokens2, :scalar)
        @while = ValueExpressionSet.new(tokens_lists[2], :scalar)
        @step = ValueExpressionSet.new(tokens_lists[4], :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end
    elsif check_template(tokens_lists, template_step_while)
      begin
        tokens1, tokens2 = control_and_start(tokens_lists[0])
        variable_name = VariableName.new(tokens1[0])
        @control = Variable.new(variable_name, :scalar, [], [])
        @start = ValueExpressionSet.new(tokens2, :scalar)
        @step = ValueExpressionSet.new(tokens_lists[2], :scalar)
        @while = ValueExpressionSet.new(tokens_lists[4], :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end
    else
      @errors << 'Syntax error'
    end

    @errors << 'TAB() not allowed' if !@start.nil? && @start.has_tab
    @errors << 'TAB() not allowed' if !@step.nil? && @step.has_tab
    @errors << 'TAB() not allowed' if !@end.nil? && @end.has_tab
    @errors << 'TAB() not allowed' if !@while.nil? && @while.has_tab
    @errors << 'TAB() not allowed' if !@until.nil? && @until.has_tab

    @warnings << 'Constant expression' if !@until.nil? && @until.constant
    @warnings << 'Constant expression' if !@while.nil? && @while.constant

    unless @until.nil?
      @warnings << "No #{@control} in expression" unless
        @until.include?(@control)
    end

    unless @while.nil?
      @warnings << "No #{@control} in expression" unless
        @while.include?(@control)
    end

    @mccabe = 1

    control = XrefEntry.new(@control.to_s, nil, true)

    @elements[:numerics] = []
    @elements[:strings] = []
    @elements[:booleans] = []
    @elements[:variables] = []
    @elements[:operators] = []
    @elements[:functions] = []
    @elements[:userfuncs] = []

    unless @start.nil?
      @elements[:numerics] += @start.numerics
      @elements[:strings] += @start.strings
      @elements[:booleans] += @start.booleans
      @elements[:variables] += [control] + @start.variables
      @elements[:operators] += @start.operators
      @elements[:functions] += @start.functions
      @elements[:userfuncs] += @start.userfuncs
    end

    unless @end.nil?
      @elements[:numerics] += @end.numerics
      @elements[:strings] += @end.strings
      @elements[:booleans] += @end.booleans
      @elements[:variables] += @end.variables
      @elements[:operators] += @end.operators
      @elements[:functions] += @end.functions
      @elements[:userfuncs] += @end.userfuncs
    end

    unless @step.nil?
      @elements[:numerics] += @step.numerics
      @elements[:strings] += @step.strings
      @elements[:booleans] += @step.booleans
      @elements[:variables] += @step.variables
      @elements[:operators] += @step.operators
      @elements[:functions] += @step.functions
      @elements[:userfuncs] += @step.userfuncs
    end

    unless @until.nil?
      @elements[:numerics] += @until.numerics
      @elements[:strings] += @until.strings
      @elements[:booleans] += @until.booleans
      @elements[:variables] += @until.variables
      @elements[:operators] += @until.operators
      @elements[:functions] += @until.functions
      @elements[:userfuncs] += @until.userfuncs
    end

    unless @while.nil?
      @elements[:numerics] += @while.numerics
      @elements[:strings] += @while.strings
      @elements[:booleans] += @while.booleans
      @elements[:variables] += @while.variables
      @elements[:operators] += @while.operators
      @elements[:functions] += @while.functions
      @elements[:userfuncs] += @while.userfuncs
    end

    @comprehension_effort += @start.comprehension_effort unless @start.nil?
    @comprehension_effort += @end.comprehension_effort unless @end.nil?
    @comprehension_effort += @step.comprehension_effort unless @step.nil?
    @comprehension_effort += @until.comprehension_effort unless @until.nil?
    @comprehension_effort += @while.comprehension_effort unless @while.nil?
  end

  def set_for_lines(line_stmt, program)
    @loopstart_line_stmt_mod = program.find_next_line_stmt_mod(line_stmt)
  end

  def set_next_lines(line_stmt, program)
    begin
      unless @control.nil?
        @nextstmt_line_stmt =
          program.find_closing_next_line_stmt(@control, line_stmt)
      end
    rescue BASICSyntaxError => e
      @program_errors << e.message
    end
  end

  def set_transfers(_)
    @transfers = []

    unless @loopstart_line_stmt_mod.nil?
      line_number = @loopstart_line_stmt_mod.line_number
      stmt = @loopstart_line_stmt_mod.statement
      @transfers << TransferRefLineStmt.new(line_number, stmt, :fornext)
    end

    unless @nextstmt_line_stmt.nil?
      line_number = @nextstmt_line_stmt.line_number
      stmt = @nextstmt_line_stmt.statement
      @transfers << TransferRefLineStmt.new(line_number, stmt, :fornext)
    end
  end

  def assign_fornext_markers(program)
    return if @control.nil?
    return if @loopstart_line_stmt_mod.nil?

    # mark as part of this fornext
    @part_of_fornext << @control

    dest_line = @loopstart_line_stmt_mod.line_number
    dest_stmt = @loopstart_line_stmt_mod.statement
    statement = program.get_statement(dest_line, dest_stmt)

    unless statement.nil?
      # mark statement's destinations
      markers = [@control]
      statement.assign_fornext_marker(@control, markers, dest_line, program)
    end
  end

  def uncache_core
    @start&.uncache
    @end&.uncache
    @step&.uncache
    @until&.uncache
    @while&.uncache
  end

  def dump
    lines = []

    lines << ("control: #{@control.dump}") unless @control.nil?
    lines << ("start:   #{@start.dump}") unless @start.nil?
    lines << ("end:     #{@end.dump}") unless @end.nil?
    lines << ("step:    #{@step.dump}") unless @step.nil?
    lines << ("until:   #{@until.dump}") unless @until.nil?
    lines << ("while:   #{@while.dump}") unless @while.nil?

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def number_for_stmts
    1
  end

  def execute_core(interpreter)
    raise BASICSyntaxError, 'uninitialized FOR' if
      @loopstart_line_stmt_mod.nil?

    raise BASICSyntaxError, 'uninitialized FOR' if
      @nextstmt_line_stmt.nil?

    from = @start.evaluate(interpreter)[0]
    step = NumericConstant.new(1)
    step = @step.evaluate(interpreter)[0] unless @step.nil?

    unless @end.nil?
      to = @end.evaluate(interpreter)[0]

      fornext_control =
        ForToControl.new(@control, from, step, to, @loopstart_line_stmt_mod)
    end

    unless @until.nil?
      fornext_control =
        ForUntilControl.new(@control, from, step, @until,
                            @loopstart_line_stmt_mod)
    end

    unless @while.nil?
      fornext_control =
        ForWhileControl.new(@control, from, step, @while,
                            @loopstart_line_stmt_mod)
    end

    interpreter.assign_fornext(fornext_control)

    interpreter.lock_variable(@control) if $options['lock_fornext'].value
    interpreter.enter_fornext(@control)

    terminated = fornext_control.front_terminated?(interpreter)

    interpreter.next_line_stmt_mod = @loopstart_line_stmt_mod
    interpreter.next_line_stmt_mod = @nextstmt_line_stmt if terminated

    untilv = nil
    untilv = @until.evaluate(interpreter)[0] unless @until.nil?
    whilev = nil
    whilev = @while.evaluate(interpreter)[0] unless @while.nil?
    io = interpreter.trace_out
    print_more_trace_info(io, from, to, step, untilv, whilev, terminated)
  end

  private

  def control_and_start(tokens)
    parts = split_on_token(tokens, '=')
    raise(BASICExpressionError, 'Incorrect initialization') if
      parts.size != 3
    raise(BASICExpressionError, 'Incorrect initialization') if
      parts[1].to_s != '='

    @errors << 'Control variable must be a variable' unless
      parts[0][0].variable?

    [parts[0], parts[2]]
  end

  def print_more_trace_info(io, from, to, step, untilv, whilev, terminated)
    io.trace_output(" #{@start} = #{from}") unless @start.numeric_constant?
    io.trace_output(" #{@end} = #{to}") unless
      @end.nil? || @end.numeric_constant?
    io.trace_output(" #{@step} = #{step}") unless
      @step.nil? || @step.numeric_constant?
    io.trace_output(" #{@until} = #{untilv}") unless @until.nil?
    io.trace_output(" #{@while} = #{whilev}") unless @while.nil?
    io.trace_output(" terminated:#{terminated}")
  end
end

# FORGET
class ForgetStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('FORGET')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      # parse variable(s)
      @variables = []

      tokens_list = split_on_group_separators(tokens_lists[0])
      tokens_list.each do |tokens|
        if tokens[0].variable?
          variable_name = VariableName.new(tokens[0])
          # FIX: parse subscripts
          variable = Variable.new(variable_name, :scalar, [], [])
          @variables << variable
          variablex = XrefEntry.new(variable.to_s, nil, false)
          @elements[:variables] += [variablex]
        else
          @errors << "Invalid variable #{tokens[0]}"
        end
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []

    @variables.each { |variable| lines << variable.dump }

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    @variables.each { |variable| interpreter.forget_value(variable) }
  end
end

# GOSUB
class GosubStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('GOSUB')]
    ]
  end

  def initialize(line_number, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1]]

    if check_template(tokens_lists, template)
      if tokens_lists[0][0].numeric_constant?
        number = IntegerConstant.new(tokens_lists[0][0])
        @dest_line = LineNumber.new(number)
        @linenums = [@dest_line]

        @comprehension_effort += 1
        @comprehension_effort += 1 if @dest_line <= line_number
      else
        @errors << "Invalid line number #{tokens_lists[0][0]}"
      end
    else
      @errors << 'Syntax error'
    end
  end

  def renumber(renumber_map)
    @dest_line = renumber_map[@dest_line]
    new_token = NumericConstantToken.new(@dest_line.line_number)
    @linenums = [@dest_line]
    @tokens[-1] = new_token
    @core_tokens[-1] = new_token
  end

  def set_destinations(interpreter, _, program)
    mod = interpreter.statement_start_index(@dest_line)

    unless mod.nil?
      dest = LineStmtMod.new(@dest_line, 0, mod)
      @dest_line_stmt_mod = program.find_exec_line_stmt_mod(dest)
    end
  end

  def set_transfers(_)
    @transfers = []

    if @dest_line_stmt_mod.nil?
      @transfers << TransferRefLineStmt.new(@dest_line, 0, :gosub) unless
        @dest_line.nil?
    else
      line_number = @dest_line_stmt_mod.line_number
      xref = TransferRefLineStmt.new(line_number, 0, :gosub)
      @transfers << xref
    end
  end

  def assign_sub_markers(program)
    return if @dest_line_stmt_mod.nil?

    dest_line = @dest_line_stmt_mod.line_number
    dest_stmt = @dest_line_stmt_mod.statement
    statement = program.get_statement(dest_line, dest_stmt)

    unless statement.nil?
      if statement.part_of_sub.nil?
        # mark statement's destinations
        statement.assign_sub_marker(dest_line, dest_line, program)
      else
        mark0 = statement.part_of_sub

        if dest_line != mark0
          statement.program_warnings <<
            "Inconsistent GOSUB target (#{mark0}, #{dest_line})"
        end
      end
    end
  end

  def check_program(program, _line_number_stmt)
    @program_errors << "Line number #{@dest_line} not found" unless
      program.line_number?(@dest_line)
  end

  def dump
    lines = [@dest_line.dump]

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    interpreter.push_return(interpreter.next_line_stmt_mod)

    raise(BASICSyntaxError, 'Line number not found') if
      @dest_line_stmt_mod.nil?

    interpreter.next_line_stmt_mod = @dest_line_stmt_mod
  end
end

# GOTO
class GotoStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('GOTO')]
    ]
  end

  def initialize(line_number, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)
    @autonext = false unless @any_if_modifiers

    template = [[1]]
    @dest_line = nil

    if check_template(tokens_lists, template)
      if tokens_lists[0][0].numeric_constant?
        number = IntegerConstant.new(tokens_lists[0][0])
        @dest_line = LineNumber.new(number)
        @linenums = [@dest_line]

        @comprehension_effort += 1
        @comprehension_effort += 1 if @dest_line <= line_number
      else
        @errors << "Invalid line number #{tokens_lists[0][0]}"
      end
    else
      @errors << 'Syntax error'
    end
  end

  def renumber(renumber_map)
    unless @dest_line.nil?
      @dest_line = renumber_map[@dest_line]
      new_token = NumericConstantToken.new(@dest_line.line_number)
      @linenums = [@dest_line]
      @tokens[-1] = new_token
      @core_tokens[-1] = new_token
    end
  end

  def set_transfers(_)
    @transfers = []

    unless @dest_line.nil?
      if @dest_line_stmt_mod.nil?
        @transfers << TransferRefLineStmt.new(@dest_line, 0, :goto) unless
          @dest_line.nil?
      else
        line_number = @dest_line_stmt_mod.line_number
        xref = TransferRefLineStmt.new(line_number, 0, :goto)
        @transfers << xref
      end
    end
  end

  def check_program(program, _line_number_stmt)
    @program_errors << "Line number #{@dest_line} not found" unless
      program.line_number?(@dest_line)
  end

  def set_destinations(interpreter, _, program)
    mod = interpreter.statement_start_index(@dest_line)

      unless mod.nil?
        dest = LineStmtMod.new(@dest_line, 0, mod)
        @dest_line_stmt_mod = program.find_exec_line_stmt_mod(dest)
      end
  end

  def dump
    lines = []

    lines << @dest_line.dump unless @dest_line.nil?

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    interpreter.next_line_stmt_mod = @dest_line_stmt_mod unless
      @dest_line_stmt_mod.nil?
  end
end

# common functions for IF statements
class AbstractIfStatement < AbstractStatement
  def initialize(line_number, keywords, tokens_lists)
    super

    if tokens_lists.class.to_s == 'Hash'
      @expression = parse_expression(tokens_lists['expr'])
      @errors << 'TAB() not allowed' if @expression.has_tab

      @warnings << 'Constant expression' if
        !@expression.nil? && @expression.constant

      @dest_line, @statement = parse_target(line_number, tokens_lists['then'])
      @else_dest_line = nil
      if tokens_lists.key?('else')
        @else_dest_line, @else_stmt = parse_target(line_number,
                                                   tokens_lists['else'])
      end

      unless @statement.nil?
        @errors << 'Invalid substatement' unless @statement.may_be_if_sub
        @warnings += @statement.warnings
      end

      unless @else_stmt.nil?
        @errors << 'Invalid substatement' unless @else_stmt.may_be_if_sub
        @warnings += @else_stmt.warnings
      end

      unless @dest_line.nil?
        @comprehension_effort += 1
        @comprehension_effort += 1 if @dest_line <= line_number
      end

      unless @else_dest_line.nil?
        @comprehension_effort += 1
        @comprehension_effort += 1 if @else_dest_line <= line_number
      end

      @elements[:numerics] = make_numeric_references
      @elements[:strings] = make_string_references
      @elements[:booleans] = make_boolean_references
      @elements[:variables] = make_variable_references
      @elements[:operators] = make_operator_references
      @elements[:functions] = make_function_references
      @elements[:userfuncs] = make_userfunc_references

      @comprehension_effort += @expression.comprehension_effort unless
        @expression.nil?

      @linenums = make_linenum_references
    else
      begin
        stack = parse_if(tokens_lists)
        @expression = parse_expression(stack['expr'])

        @errors << 'TAB() not allowed' if
          !@expression.nil? && @expression.has_tab

        @warnings << 'Constant expression' if
          !@expression.nil? && @expression.constant

        @dest_line, @statement = parse_target(line_number, stack['then'])
        @else_dest_line = nil
        if stack.key?('else')
          @else_dest_line, @else_stmt = parse_target(line_number,
                                                     stack['else'])
        end

        unless @statement.nil?
          @errors << 'Invalid substatement' unless @statement.may_be_if_sub
          @warnings += @statement.warnings
        end

        unless @else_stmt.nil?
          @errors << 'Invalid substatement' unless @else_stmt.may_be_if_sub
          @warnings += @else_stmt.warnings
        end

        unless @dest_line.nil?
          @comprehension_effort += 1
          @comprehension_effort += 1 if @dest_line <= line_number
        end

        unless @else_dest_line.nil?
          @comprehension_effort += 1
          @comprehension_effort += 1 if @else_dest_line <= line_number
        end

        @elements[:numerics] = make_numeric_references
        @elements[:strings] = make_string_references
        @elements[:booleans] = make_boolean_references
        @elements[:variables] = make_variable_references
        @elements[:operators] = make_operator_references
        @elements[:functions] = make_function_references
        @elements[:userfuncs] = make_userfunc_references

        @comprehension_effort += @expression.comprehension_effort unless
          @expression.nil?

        @linenums = make_linenum_references
      rescue BASICExpressionError => e
        @errors << ("Syntax Error: #{e.message}")
      end
    end

    # autonext to next statement unless both THEN and ELSE are numbers
    @autonext = @dest_line.nil? || @else_dest_line.nil?

    unless @statement.nil?
      @comprehension_effort += @statement.comprehension_effort
    end

    unless @else_stmt.nil?
      @comprehension_effort += @else_stmt.comprehension_effort
    end

    @mccabe += 1
    @mccabe += @statement.mccabe unless @statement.nil?
    @mccabe += @else_stmt.mccabe unless @else_stmt.nil?

    @is_if_no_else = @else_dest_line.nil? && @else_stmt.nil?
  end

  def set_for_lines(line_stmt_mod, program)
    @statement&.set_for_lines(line_stmt_mod, program)
    @else_stmt&.set_for_lines(line_stmt_mod, program)
  end

  def set_next_lines(line_stmt_mod, program)
    @statement&.set_next_lines(line_stmt_mod, program)
    @else_stmt&.set_next_lines(line_stmt_mod, program)
  end

  def renumber(renumber_map)
    unless @dest_line.nil?
      @dest_line = renumber_map[@dest_line]
      new_token = NumericConstantToken.new(@dest_line.line_number)

      index = 0
      @tokens.each_with_index do |token, i|
        index = i if token.to_s == 'THEN'
      end

      @tokens[index + 1] = new_token

      index = 0
      @core_tokens.each_with_index do |token, i|
        index = i if token.to_s == 'THEN'
      end

      @core_tokens[index + 1] = new_token
    end

    unless @else_dest_line.nil?
      @else_dest_line = renumber_map[@else_dest_line]
      new_token = NumericConstantToken.new(@else_dest_line.line_number)
      @tokens[-1] = new_token
      @core_tokens[-1] = new_token
    end

    @linenums = make_linenum_references

    @statement&.renumber(renumber_map)
    @else_stmt&.renumber(renumber_map)
  end

  def set_destinations(interpreter, _, program)
    unless @dest_line.nil?
      mod = interpreter.statement_start_index(@dest_line)

      unless mod.nil?
        dest = LineStmtMod.new(@dest_line, 0, mod)
        @dest_line_stmt_mod = program.find_exec_line_stmt_mod(dest)
      end
    end

    unless @else_dest_line.nil?
      mod = interpreter.statement_start_index(@else_dest_line)

      unless mod.nil?
        dest = LineStmtMod.new(@else_dest_line, 0, mod)
        @else_dest_line_stmt_mod = program.find_exec_line_stmt_mod(dest)
      end
    end

    @statement&.set_destinations(interpreter, _, program)
    @else_stmt&.set_destinations(interpreter, _, program)
  end

  def set_autonext_line_stmt(line_stmt_mod)
    @autonext_line_stmt = line_stmt_mod

    @statement&.set_autonext_line_stmt(line_stmt_mod)
    @else_stmt&.set_autonext_line_stmt(line_stmt_mod)
  end

  def set_autonext_line(line_stmt_mod)
    @autonext_line = line_stmt_mod

    @statement&.set_autonext_line(line_stmt_mod)
    @else_stmt&.set_autonext_line(line_stmt_mod)
  end

  def set_transfers(user_function_start_lines)
    @transfers = []

    unless @dest_line.nil?
      if @dest_line_stmt_mod.nil?
        @transfers << TransferRefLineStmt.new(@dest_line, 0, :ifthen)
      else
        line_number = @dest_line_stmt_mod.line_number
        xref = TransferRefLineStmt.new(line_number, 0, :ifthen)
        @transfers << xref
      end
    end

    @statement&.set_transfers(user_function_start_lines)

    unless @else_dest_line.nil?
      if @else_dest_line_stmt_mod.nil?
        @transfers << TransferRefLineStmt.new(@else_dest_line, 0, :ifthen)
      else
        line_number = @else_dest_line_stmt_mod.line_number
        xref = TransferRefLineStmt.new(line_number, 0, :ifthen)
        @transfers << xref
      end
    end

    @else_stmt&.set_transfers(user_function_start_lines)

    # autonext to next line if no ELSE
    if @autonext_line && @else_dest_line.nil? && @else_stmt.nil?
      line_number = @autonext_line.line_number
      stmt = @autonext_line.statement

      # do not change this to @transfers_auto
      @transfers << TransferRefLineStmt.new(line_number, stmt, :auto)
    end

    @transfers += @statement.transfers unless @statement.nil?
    @transfers += @else_stmt.transfers unless @else_stmt.nil?
  end

  def uncache_core
    @expression&.uncache
    @statement&.uncache
    @else_stmt&.uncache
  end

  def dump
    lines = []

    lines += @expression.dump unless @expression.nil?
    lines << @dest_line.dump unless @dest_line.nil?
    lines += @statement.dump unless @statement.nil?
    lines << @else_dest_line.dump unless @else_dest_line.nil?
    lines += @else_stmt.dump unless @else_stmt.nil?

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def check_program(program, _line_number_stmt)
    if @dest_line.nil? && @statement.nil?
      @program_errors << 'Invalid or missing line number'
    end

    unless @dest_line.nil? || program.line_number?(@dest_line)
      @program_errors << "Line number #{@dest_line} not found"
    end

    unless @else_dest_line.nil? || program.line_number?(@else_dest_line)
      @program_errors << "Line number #{@else_dest_line} not found"
    end
  end

  def number_for_stmts
    number = 0

    number += @statement.number_for_stmts unless @statement.nil?
    number += @else_stmt.number_for_stmts unless @else_stmt.nil?

    number
  end

  def execute_core(interpreter)
    values = @expression.evaluate(interpreter)

    raise(BASICExpressionError, 'Too many or too few values') unless
      values.size == 1

    result = values[0]

    result = BooleanConstant.new(result) unless
      result.class.to_s == 'BooleanConstant'

    if result.value
      interpreter.next_line_stmt_mod = @dest_line_stmt_mod unless
        @dest_line_stmt_mod.nil?

      if !@statement.nil? && !@else_stmt.nil? && $options['extend_if'].value
        # go to next numbered line, not next statement
        interpreter.next_line_stmt_mod = @autonext_line
      end

      @statement&.execute_core(interpreter)
    else
      interpreter.next_line_stmt_mod = @else_dest_line_stmt_mod unless
        @else_dest_line_stmt_mod.nil?

      if @else_dest_line.nil? && @else_stmt.nil? && $options['extend_if'].value
        # go to next numbered line, not next statement
        interpreter.next_line_stmt_mod = @autonext_line
      end

      @else_stmt&.execute_core(interpreter)
    end

    s = " #{@expression}: #{result}"
    io = interpreter.trace_out
    io.trace_output(s)
  end

  private

  def parse_if(tokens_lists)
    stack = []
    new_dict = { 'expr' => [], 'then' => [] }
    stack << new_dict
    dict = stack[-1]
    state = 1

    tokens_lists.each do |tokens_list|
      handled = false
      case state
      when 1
        if tokens_list == 'THEN'
          state = 2
        elsif tokens_list.class.to_s == 'KeywordToken'
          if tokens_list.to_s == 'GOTO'
            state = 4
          else
            dict['expr'] << tokens_list
          end
        else
          dict['expr'] += tokens_list
        end
        handled = true
      when 2
        unless handled
          if tokens_list == 'ELSE'
            dict['else'] = []
            state = 3
          elsif tokens_list == 'IF' && dict['then'].empty?
            new_dict = { 'expr' => [], 'then' => [] }
            dict['then'] = new_dict
            stack << new_dict
            dict = stack[-1]
            state = 1
          elsif tokens_list.class.to_s == 'KeywordToken'
            dict['then'] << tokens_list
          else
            dict['then'] += tokens_list
          end
          handled = true
        end
      when 3
        unless handled
          if tokens_list == 'ELSE'
            stack.pop
            # TODO: exit if stack.empty
            dict = stack[-1]
            dict['else'] = []
          elsif tokens_list == 'IF' && dict['else'].empty?
            new_dict = { 'expr' => [], 'then' => [] }
            dict['else'] = new_dict
            stack << new_dict
            dict = stack[-1]
            state = 1
          elsif tokens_list.class.to_s == 'KeywordToken'
            dict['else'] << tokens_list
          else
            dict['else'] += tokens_list
          end
          handled = true
        end
      when 4
        unless handled
          if dict['then'].empty?
            dict['then'] += tokens_list
          else
            raise(BASICSyntaxError, 'THEN without matching IF')
          end
          handled = true
        end
      end
    end

    stack[0]
  end

  def print_dict(dict)
    expr_s = '['
    x0 = dict['expr']

    x0.each do |x|
      expr_s += if x.class.to_s == 'Array'
                  "[#{x.map(&:to_s).join(', ')}]"
                else
                  x.to_s
                end
      expr_s += ', '
    end

    expr_s += ']'
    x1 = dict['then']

    if x1.class.to_s == 'Array'
      ax1 = []
      x1.each do |x|
        ax1 << if x.class.to_s == 'Array'
                 "[#{x.map(&:to_s).join(', ')}]"
               else
                 x.to_s
               end
      end
      then_s = "[#{ax1.join(', ')}]"
    else
      then_s = 'DICT'
    end

    else_s = ''

    if dict.key?('else')
      x2 = dict['else']
      if x2.class.to_s == 'Array'
        ax2 = []
        x2.each do |x|
          ax2 << if x.class.to_s == 'Array'
                   "[#{x.map(&:to_s).join(', ')}]"
                 else
                   x.to_s
                 end
        end
        else_s = "[#{ax2.join(', ')}]"
      else
        else_s = 'DICT'
      end
    end
  end

  def make_numeric_references
    nums = []
    nums += @expression.numerics unless @expression.nil?
    nums += @statement.numerics unless @statement.nil?
    nums += @else_stmt.numerics unless @else_stmt.nil?
    nums
  end

  def make_string_references
    strs = []
    strs += @expression.strings unless @expression.nil?
    strs += @statement.strings unless @statement.nil?
    strs += @else_stmt.strings unless @else_stmt.nil?
    strs
  end

  def make_boolean_references
    bools = []
    bools += @expression.booleans unless @expression.nil?
    bools += @statement.booleans unless @statement.nil?
    bools += @else_stmt.booleans unless @else_stmt.nil?
    bools
  end

  def make_variable_references
    vars = []
    vars += @expression.variables unless @expression.nil?
    vars += @statement.variables unless @statement.nil?
    vars += @else_stmt.variables unless @else_stmt.nil?
    vars
  end

  def make_operator_references
    vars = []
    vars += @expression.operators unless @expression.nil?
    vars += @statement.operators unless @statement.nil?
    vars += @else_stmt.operators unless @else_stmt.nil?
    vars
  end

  def make_function_references
    vars = []
    vars += @expression.functions unless @expression.nil?
    vars += @statement.functions unless @statement.nil?
    vars += @else_stmt.functions unless @else_stmt.nil?
    vars
  end

  def make_userfunc_references
    vars = []
    vars += @expression.userfuncs unless @expression.nil?
    vars += @statement.userfuncs unless @statement.nil?
    vars += @else_stmt.userfuncs unless @else_stmt.nil?
    vars
  end

  def make_linenum_references
    nums = []
    nums << @dest_line unless @dest_line.nil?
    nums << @else_dest_line unless @else_dest_line.nil?
    nums
  end

  def parse_target(line_number, tokens)
    destination = nil
    statement = nil

    if tokens.class.to_s == 'Hash'
      statement = IfStatement.new(line_number, nil, tokens)
    elsif tokens.size == 1 && tokens[0].numeric_constant?
      number = IntegerConstant.new(tokens[0])
      destination = LineNumber.new(number)
    else
      statement_factory = StatementFactory.instance

      text = tokens.map(&:to_s).join(' ')

      statement =
        statement_factory.create_statement(line_number, text, tokens.flatten)

      @errors += statement.errors
    end

    [destination, statement]
  end
end

# IF/THEN
class IfStatement < AbstractIfStatement
  def self.lead_keywords
    [
      [KeywordToken.new('IF')]
    ]
  end

  def self.extra_keywords
    %w[THEN ELSE]
  end

  private

  def parse_expression(tokens)
    expression = nil

    begin
      expression = ValueExpressionSet.new(tokens, :scalar)
    rescue BASICExpressionError => e
      @errors << e.message
    end

    expression
  end
end

# INPUT
class InputStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('INPUT')]
    ]
  end

  include FileFunctions
  include InputFunctions

  def initialize(_, _, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      items = split_tokens(tokens_lists[0], false)
      @items = tokens_to_expressions(items, :scalar, false)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @prompt = extract_prompt(@items)
      @elements = make_references(@items, @file_tokens, @prompt)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }

      @mccabe += @items.size
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :read)

    prompt = nil

    unless @prompt.nil?
      prompts = @prompt.evaluate(interpreter)
      prompt = prompts[0]
    end

    # create list of variables with subscripts
    item_names = []

    @items.each do |item|
      targets = item.evaluate(interpreter)
      targets.each do |target|
        item_names << target
      end
    end

    # get all of the needed values
    if fh.nil?
      # from console
      values = input_values(fhr, interpreter, prompt, item_names.size)
      fhr.implied_newline
    else
      # from file
      values = fhr.input(interpreter)
    end

    raise BASICRuntimeError, :te_too_few if values.size < item_names.size

    name_value_pairs =
      zip(item_names, values[0..item_names.length])

    name_value_pairs.each do |hash|
      variable = hash['name']
      value = hash['value']
      interpreter.set_value(variable, value)
    end

    interpreter.clear_previous_lines
  end
end

# common functions for LET and LET-less statements
class AbstractLetStatement < AbstractStatement
  def set_transfers(user_function_start_lines)
    @transfers = []

    unless @assignment.nil?
      @transfers += @assignment.destinations(user_function_start_lines)
    end
  end

  def uncache_core
    @assignment.uncache
  end

  def dump
    lines = []

    lines += @assignment.dump unless @assignment.nil?

    @modifiers&.each { |item| lines += item.dump }

    lines
  end
end

# common functions for scalar LET and LET-less statement
class AbstractScalarLetStatement < AbstractLetStatement
  def initialize(_, _, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[3, '>=']]

    if check_template(tokens_lists, template)
      begin
        @assignment = Assignment.new(tokens_lists[0], :scalar)

        if @assignment.count_target.zero?
          @errors << 'Assignment must have left-hand value(s)'
        end

        if @assignment.count_value.zero?
          @errors << 'Assignment must have right-hand value(s)'
        end

        @errors << 'TAB() not allowed' if @assignment.has_tab

        @warnings << 'Extra values ignored' if
          @assignment.count_value > @assignment.count_target

        @warnings += @assignment.warnings
        @elements = make_references(nil, @assignment)

        @comprehension_effort += @assignment.comprehension_effort
      rescue BASICExpressionError => e
        @errors << e.message
      end
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    l_values = @assignment.eval_target(interpreter)

    r_values = @assignment.eval_value(interpreter)

    # more left-hand values -> repeat last rhs
    # more rhs -> drop extra values
    l_values.each_with_index do |l_value, index|
      j = [index, r_values.count - 1].min
      r_value = r_values[j]

      # if l_value is a function name
      # replace with current function name
      l_value = interpreter.current_user_function if
        l_value.class.to_s == 'UserFunction'

      interpreter.set_value(l_value, r_value)
    end
  end
end

# LET
class LetStatement < AbstractScalarLetStatement
  def self.lead_keywords
    [
      [KeywordToken.new('LET')]
    ]
  end
end

# LET-less assignment
class LetLessStatement < AbstractScalarLetStatement
  def self.lead_keywords
    [
      []
    ]
  end
end

# LINE INPUT
class LineInputStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('LINE'), KeywordToken.new('INPUT')],
      [KeywordToken.new('LINPUT')]
    ]
  end

  include FileFunctions
  include InputFunctions

  def initialize(_, _, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      items = split_tokens(tokens_lists[0], false)
      @items = tokens_to_expressions(items, :scalar, false)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @prompt = extract_prompt(@items)
      @elements = make_references(@items, @file_tokens, @prompt)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }

      @mccabe += @items.size
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :read)

    prompt = nil

    unless @prompt.nil?
      prompts = @prompt.evaluate(interpreter)
      prompt = prompts[0]
    end

    if fh.nil?
      values = input_values(fhr, interpreter, prompt, @items.size)
      fhr.implied_newline
    else
      values = fhr.line_input(interpreter)
    end

    name_value_pairs =
      zip(@items, values[0..@items.length])

    name_value_pairs.each do |hash|
      variables = hash['name'].evaluate(interpreter)
      variable = variables[0]
      value = hash['value']
      interpreter.set_value(variable, value)
    end

    interpreter.clear_previous_lines
  end

  private

  def input_values(fhr, interpreter, prompt, count)
    values = []

    while values.size < count
      remaining = count - values.size
      fhr.prompt(prompt, remaining)
      values += fhr.line_input(interpreter)

      prompt = nil
    end

    values
  end
end

# NEXT
class NextStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('NEXT')]
    ]
  end

  attr_reader :controls

  def initialize(_, keywords, tokens_lists)
    super

    template1 = [[1, '>=']]
    template2 = []

    if check_template(tokens_lists, template1)
      # parse control variables
      @controls = []

      tokens_list = split_on_group_separators(tokens_lists[0])
      tokens_list.each do |tokens|
        if tokens.empty?
          @controls << EmptyVariable.new
        elsif tokens.size == 1 && tokens[0].variable?
          variable_name = VariableName.new(tokens[0])
          control = Variable.new(variable_name, :scalar, [], [])
          @controls << control
          controlx = XrefEntry.new(control.to_s, nil, false)
          @elements[:variables] += [controlx]
        else
          @errors << "Invalid control variable #{tokens[0]}"
        end
      end
    elsif check_template(tokens_lists, template2)
      @controls = [EmptyVariable.new]
    else
      @errors << 'Syntax error'
    end
  end

  def has_control(control)
    @controls.include?(control)
  end

  def dump
    lines = []

    @controls&.each do |control|
      lines << control.dump unless control.empty?
    end

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    max = @controls.size

    # for each control, until we find one that is not terminated
    found_unterminated = false
    index = 0

    while !found_unterminated && index < max
      if @controls[index].empty?
        control_name = interpreter.top_fornext
        fornext_control = interpreter.retrieve_fornext(control_name)
      else
        fornext_control = interpreter.retrieve_fornext(@controls[index])
      end

      bump_early = fornext_control.bump_early?

      # change control variable value for FOR-WHILE and FOR-UNTIL
      fornext_control.bump_control(interpreter) if bump_early

      # check control variable value
      # if matches end value, stop here
      terminated = fornext_control.terminated?(interpreter)
      io = interpreter.trace_out
      s = " terminated:#{terminated}"
      io.trace_output(s)

      if terminated
        interpreter.unlock_variable(@controls[index]) if
          $options['lock_fornext'].value

        interpreter.exit_fornext(fornext_control.forget,
                                 fornext_control.control)
      else
        # set next line from top item
        interpreter.next_line_stmt_mod = fornext_control.start_line_stmt_mod
        # change control variable value for FOR-TO
        fornext_control.bump_control(interpreter) unless bump_early

        found_unterminated = true
      end

      index += 1
    end
  end
end

# ON ERROR GOTO
class OnErrorStatement < AbstractStatement
  def self.lead_keywords
    [
      [
        KeywordToken.new('ON'),
        KeywordToken.new('ERROR'),
        KeywordToken.new('GOTO')
      ]
    ]
  end

  def initialize(line_number, keywords, tokens_lists)
    super

    template = [[1]]

    if check_template(tokens_lists, template)
      destinations = tokens_lists[0]
      line_nums = split_tokens(destinations, false)
      destinations = line_nums[0]
      token = destinations[0]

      if token.numeric_constant?
        if token.to_i.zero?
          @dest_line = nil
          @linenums = []
        else
          number = IntegerConstant.new(token)
          @dest_line = LineNumber.new(number)
          @linenums = [@dest_line]

          @comprehension_effort += 1
          @comprehension_effort += 1 if @dest_line <= line_number
        end
      else
        @errors << "Invalid line number #{destination}"
      end

      @mccabe += 1
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []

    lines << @dest_line.dump unless @dest_line.nil?

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def set_destinations(interpreter, _, program)
    mod = interpreter.statement_start_index(@dest_line)
 
    unless mod.nil?
      dest = LineStmtMod.new(@dest_line, 0, mod)
      @dest_line_stmt_mod = program.find_exec_line_stmt_mod(dest)
    end
  end

  def assign_on_error_markers(program)
    return if @dest_line_stmt_mod.nil?

    dest_line = @dest_line_stmt_mod.line_number
    dest_stmt = @dest_line_stmt_mod.statement
    statement = program.get_statement(dest_line, dest_stmt)

    unless statement.nil?
      if statement.part_of_on_error.nil?
        # mark statement's destinations
        statement.assign_on_error_marker(dest_line, dest_line, program)
      else
        mark0 = statement.part_of_on_error
        if dest_line != mark0
          statement.program_warnings <<
            "Inconsistent ON-ERROR target (#{mark0}, #{dest_line})"
        end
      end
    end
  end

  def set_transfers(_)
    @transfers = []

    unless @dest_line_stmt_mod.nil?
      line_number = @dest_line_stmt_mod.line_number
      @transfers << TransferRefLineStmt.new(line_number, 0, :onerror)
    end
  end

  def check_program(program, _line_number_stmt)
    if !@dest_line.nil? && !program.line_number?(@dest_line)
      @program_errors << "Line number #{@dest_line} not found"
    end
  end

  def execute_core(interpreter)
    interpreter.seterrorgoto(@dest_line)
  end

  def renumber(renumber_map)
    unless @dest_line.nil?
      @dest_line = renumber_map[@dest_line]
      new_token = NumericConstantToken.new(@dest_line.line_number)
      @linenums = [@dest_line]
      @tokens[-1] = new_token
      @core_tokens[-1] = new_token
    end
  end
end

# ON GOTO/ON GOSUB
class OnStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ON')]
    ]
  end

  def self.extra_keywords
    %w[GOTO THEN GOSUB]
  end

  def initialize(line_number, keywords, tokens_lists)
    super

    @dest_lines = nil
    @expression = nil

    template1 = [[1, '>='], 'GOTO', [1, '>=']]
    template2 = [[1, '>='], 'THEN', [1, '>=']]
    template3 = [[1, '>='], 'GOSUB', [1, '>=']]

    if check_template(tokens_lists, template1) ||
       check_template(tokens_lists, template2) ||
       check_template(tokens_lists, template3)
      expression = tokens_lists[0]

      begin
        @expression = ValueExpressionSet.new(expression, :scalar)
      rescue BASICExpressionError => e
        @errors << e.message
      end

      @errors << 'TAB() not allowed' if @expression.has_tab
      @warnings << 'Constant expression' if @expression.constant
      @elements = make_references(nil, @expression)

      @gosub = tokens_lists[1] == 'GOSUB'

      destinations = tokens_lists[2]
      line_nums = split_tokens(destinations, false)
      @dest_lines = []

      line_nums.each do |line_num|
        if line_num.size == 1
          token = line_num[0]
          if token.numeric_constant?
            number = IntegerConstant.new(token)
            @dest_lines << LineNumber.new(number)
          else
            @errors << "Invalid line number #{destination}"
          end
        else
          @errors << "Invalid line specification #{line_num}"
        end
      end

      @linenums = @dest_lines
      @comprehension_effort += @expression.comprehension_effort

      @dest_lines.each do |dest_line|
        @comprehension_effort += 1
        @comprehension_effort += 1 if dest_line <= line_number
      end

      @mccabe += @dest_lines.size
    else
      @errors << 'Syntax error'
    end
  end

  def set_destinations(interpreter, _, program)
    unless @dest_lines.nil?
      @dest_line_stmt_mods = []

      @dest_lines.each do |dest_line|
        mod = interpreter.statement_start_index(dest_line)

        unless mod.nil?
          dest = LineStmtMod.new(dest_line, 0, mod)
          @dest_line_stmt_mods << program.find_exec_line_stmt_mod(dest)
        end
      end
    end
  end

  def check_program(program, _line_number_stmt)
    @dest_lines&.each do |destination|
      unless program.line_number?(destination)
        @program_errors << "Line number #{destination} not found"
      end
    end
  end

  def renumber(renumber_map)
    new_dest_lines = []

    @dest_lines.each do |dest_line|
      new_dest_lines << renumber_map[dest_line]
    end

    index = 0
    @tokens.each_with_index do |token, i|
      index = i if token.to_s == 'THEN'
      index = i if token.to_s == 'GOTO'
      index = i if token.to_s == 'GOSUB'
    end

    new_dest_lines.each do |dest_line|
      new_token = NumericConstantToken.new(dest_line.line_number)
      @tokens[index + 1] = new_token

      index += 2
    end

    @dest_lines = new_dest_lines
    @linenums = @dest_lines
  end

  def set_transfers(_)
    @transfers = []

    @dest_line_stmt_mods.each do |dest_line_stmt_mod|
      line_number = dest_line_stmt_mod.line_number
      @transfers << TransferRefLineStmt.new(line_number, 0, :goto)
    end
  end

  def uncache_core
    @expression.uncache
  end

  def dump
    lines = []

    lines += @expression.dump unless @expression.nil?

    @dest_lines&.each { |dest_line| lines << dest_line.dump }

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    raise(BASICSyntaxError, 'Line number not found') if
      @dest_line_stmt_mods.nil?

    values = @expression.evaluate(interpreter)

    raise(BASICExpressionError, 'Expecting one value') unless values.size == 1

    value = values[0]

    raise(BASICExpressionError, 'Invalid value') unless value.numeric_constant?

    io = interpreter.trace_out
    io.trace_output(" #{@expression} = #{value}")
    index = value.to_i

    raise BASICRuntimeError, :te_val_out if
      index < 1 || index > @dest_line_stmt_mods.size

    interpreter.push_return(interpreter.next_line_stmt_mod) if @gosub

    # get destination in list
    interpreter.next_line_stmt_mod = @dest_line_stmt_mods[index - 1]
  end
end

# OPEN
class OpenStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('OPEN')]
    ]
  end

  def self.extra_keywords
    %w[FOR INPUT OUTPUT APPEND AS FILE]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template_input_as = [[1, '>='], 'FOR', 'INPUT', 'AS', [1, '>=']]

    template_input_as_file =
      [[1, '>='], 'FOR', 'INPUT', 'AS', 'FILE', [1, '>=']]

    template_output_as = [[1, '>='], 'FOR', 'OUTPUT', 'AS', [1, '>=']]

    template_output_as_file =
      [[1, '>='], 'FOR', 'OUTPUT', 'AS', 'FILE', [1, '>=']]

    template_append_as = [[1, '>='], 'FOR', 'APPEND', 'AS', [1, '>=']]

    template_append_as_file =
      [[1, '>='], 'FOR', 'APPEND', 'AS', 'FILE', [1, '>=']]

    if check_template(tokens_lists, template_input_as) ||
       check_template(tokens_lists, template_input_as_file)

      @filename_expression = ValueExpressionSet.new(tokens_lists[0], :scalar)
      @errors << 'TAB() not allowed' if @filename_expression.has_tab
      @filenum_expression = ValueExpressionSet.new(tokens_lists[-1], :scalar)
      @errors << 'TAB() not allowed' if @filenum_expression.has_tab

      @elements =
        make_references(nil, @filename_expression, @filenum_expression)

      @mode = :read

      @comprehension_effort += @filenum_expression.comprehension_effort
      @comprehension_effort += @filename_expression.comprehension_effort

    elsif check_template(tokens_lists, template_output_as) ||
          check_template(tokens_lists, template_output_as_file)

      @filename_expression = ValueExpressionSet.new(tokens_lists[0], :scalar)
      @errors << 'TAB() not allowed' if @filename_expression.has_tab
      @filenum_expression = ValueExpressionSet.new(tokens_lists[-1], :scalar)
      @errors << 'TAB() not allowed' if @filenum_expression.has_tab

      @elements =
        make_references(nil, @filename_expression, @filenum_expression)

      @mode = :print

      @comprehension_effort += @filenum_expression.comprehension_effort
      @comprehension_effort += @filename_expression.comprehension_effort

    elsif check_template(tokens_lists, template_append_as) ||
          check_template(tokens_lists, template_append_as_file)

      @filename_expression = ValueExpressionSet.new(tokens_lists[0], :scalar)
      @errors << 'TAB() not allowed' if @filename_expression.has_tab
      @filenum_expression = ValueExpressionSet.new(tokens_lists[-1], :scalar)
      @errors << 'TAB() not allowed' if @filenum_expression.has_tab

      @elements =
        make_references(nil, @filename_expression, @filenum_expression)

      @mode = :append

      @comprehension_effort += @filenum_expression.comprehension_effort
      @comprehension_effort += @filename_expression.comprehension_effort
    else
      @errors << 'Syntax error'
    end
  end

  def uncache_core
    @filenum_expression.uncache
    @filename_expression.uncache
  end

  def dump
    lines = []

    lines += @filename_expression.dump unless @filename_expression.nil?
    lines += @filenum_expression.dump unless @filenum_expression.nil?

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    filenames = @filename_expression.evaluate(interpreter)
    filename = filenames[0]
    fhs = @filenum_expression.evaluate(interpreter)
    fh = FileHandle.new(fhs[0])
    interpreter.open_file(filename, fh, @mode)
  end
end

# OPTION
class OptionStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('OPTION')]
    ]
  end

  def self.extra_keywords
    $options.keys.map(&:upcase)
  end

  def initialize(_, keywords, tokens_lists)
    super

    extras = OptionStatement.extra_keywords
    template = [extras, [1, '>=']]

    if check_template(tokens_lists, template)
      kwd = tokens_lists[0].to_s.upcase
      @key = kwd.downcase

      if $options[@key].types.include?(:runtime)
        expression_tokens = split_tokens(tokens_lists[1], true)
        @expression = ValueExpressionSet.new(expression_tokens[0], :scalar)
        @errors << 'TAB() not allowed' if @expression.has_tab

        @elements = make_references(nil, @expression)

        @comprehension_effort += @expression.comprehension_effort
      else
        @errors << ("Cannot set option #{kwd}")
      end
    elsif tokens_lists.size == 1 &&
          extras.include?(tokens_lists[0].to_s)
      kwd = tokens_lists[0].to_s.upcase
      @key = kwd.downcase

      @errors << ("Cannot set option #{kwd}") unless
        $options[@key].types.include?(:runtime)
    else
      @errors << 'Syntax error'
    end
  end

  def uncache_core
    @expression&.uncache
  end

  def dump
    lines = []

    lines += @expression.dump unless @expression.nil?

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    if @expression.nil?
      interpreter.pop_option(@key)
    else
      values = @expression.evaluate(interpreter)
      value0 = values[0]

      interpreter.push_option(@key, value0.to_v)
    end
  end
end

# PRINT
class PrintStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('PRINT')]
    ]
  end

  include FileFunctions
  include PrintFunctions

  def self.extra_keywords
    ['USING']
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    # build list: exp, cc, exp, cc, 'USING' exp, cc, exp, cc
    tokens = tokens_lists.flatten
    list = split_keywords(tokens)

    @items = []

    if list.empty?
      expressions = tokens_to_expressions([], :scalar)
      @items << expressions
    else
      list.each do |item|
        if item.class.to_s == 'Array'
          tokens_lists = split_tokens(item, true)
          expressions = tokens_to_expressions(tokens_lists, :scalar)
          @items << expressions
        else
          @items << item
        end
      end
    end

    # if list first item is expression
    #   extract possible file handle
    @file_tokens = nil
    if !@items.empty? && (@items[0].class.to_s == 'Array') && !@items[0].empty?
      @file_tokens = extract_file_handle(@items[0])
    end

    # end with
    #   @file_tokens : exp or nil
    #   @items : list either expression, cc, or keyword

    # if item is keyword then it must be 'USING'
    @items.each do |item|
      if item.class.to_s != 'Array' && !(item.keyword? && item.to_s == 'USING')
        @errors << 'Syntax error'
      end
    end

    @elements = make_references(nil, @file_tokens)

    @items.each do |item|
      if item.class.to_s == 'Array'
        elements = make_references(item)

        elements.each { |k, v| @elements[k] += v }

        item.each { |it| @comprehension_effort += it.comprehension_effort }
      elsif item.keyword?
        @comprehension_effort += 1
      end
    end

    ## @errors << 'Delimiter required' if any_implied_carriage(@items)
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    j = 0
    while j < @items.size
      item = @items[j]

      if item.class.to_s == 'Array'
        i = 0
        last_was_carriage = true

        while i < item.size
          it = item[i]

          # insert an implicit carriage control
          fhr.implied unless it.carriage_control? || last_was_carriage

          if it.carriage_control?
            it.print(fhr)
          else
            it.print(fhr, interpreter)
          end

          last_was_carriage = it.carriage_control?

          i += 1
        end
      else
        # item must be 'USING'
        j += 1

        raise BASICRuntimeError, :te_no_fmt if j >= @items.size

        # extract formats
        item = @items[j]

        format_spec, items = extract_format(item, interpreter)

        raise BASICRuntimeError, :te_no_fmt if format_spec.nil?

        # split format spec into formats
        formats = split_format(format_spec)
        fhr = interpreter.console_io

        # FIX: if item is not Array, throw exception

        last_was_carriage = true

        i = 0

        formats.each do |format|
          constant = nil

          if format.wants_item
            # skip all of the separators
            i += 1 while i < items.size && items[i].carriage_control?

            raise BASICRuntimeError, :te_few_fmt if i == items.size

            constants = items[i].evaluate(interpreter)

            constant = constants[0]

            i += 1
          end

          text = format.pretty_format(constant)
          text.print(fhr)

          last_was_carriage = false
        end

        while i < items.size
          item = items[i]

          # insert an implicit carriage control
          fhr.implied unless item.carriage_control? || last_was_carriage

          if item.carriage_control?
            item.print(fhr)
          else
            item.print(fhr, interpreter)
          end

          last_was_carriage = item.carriage_control?

          i += 1
        end
      end

      j += 1
    end
  end
end

# RANDOMIZE
class RandomizeStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('RANDOMIZE')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def dump
    lines = ['']

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    interpreter.new_random
  end
end

# READ
class ReadStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('READ')]
    ]
  end

  include FileFunctions
  include ReadFunctions

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      items = split_tokens(tokens_lists[0], false)
      @items = tokens_to_expressions(items, :scalar, false)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @elements = make_references(@items, @file_tokens)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }

      @mccabe += @items.size
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    ds = interpreter.get_data_store(fh)

    @items.each do |item|
      targets = item.evaluate(interpreter)
      targets.each do |target|
        value = ds.read
        interpreter.set_value(target, value)
      end
    end

    interpreter.clear_previous_lines
  end
end

# RESTORE
class RestoreStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('RESTORE')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def dump
    lines = ['']

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    ds = interpreter.get_data_store(nil)
    ds.reset
  end
end

# RESUME
class ResumeStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('RESUME')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)
    @autonext = false unless @any_if_modifiers

    template_0 = []
    template_1 = [[1, '>=']]

    target = nil
    if check_template(tokens_lists, template_0)
      target = nil
    elsif check_template(tokens_lists, template_1)
      target = tokens_lists[0][0]
    else
      @errors << 'Syntax error'
    end

    @dest_line = nil

    unless target.nil?
      begin
        number = IntegerConstant.new(target)
        @dest_line = LineNumber.new(number)
        @linenums = [@dest_line]
      rescue BASICSyntaxError
        @errors << 'Invalid target'
      end
    end
  end

  def dump
    lines = ['']

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def set_destinations(interpreter, _, program)
    mod = interpreter.statement_start_index(@dest_line)
 
    unless mod.nil?
      dest = LineStmtMod.new(@dest_line, 0, mod)
      @dest_line_stmt_mod = program.find_exec_line_stmt_mod(dest)
    end
  end

  def set_transfers(_)
    @transfers = []

    unless @dest_line_stmt_mod.nil?
      line_number = @dest_line_stmt_mod.line_number
      @transfers << TransferRefLineStmt.new(line_number, 0, :resume)
    end
  end

  def execute_core(interpreter)
    interpreter.resume(@dest_line)
  end
end

# RETURN
class ReturnStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('RETURN')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)
    @autonext = false unless @any_if_modifiers

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def dump
    lines = ['']

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    interpreter.next_line_stmt_mod = interpreter.pop_return
  end
end

# SLEEP
class SleepStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('SLEEP')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template_0 = []
    template_1 = [[1, '>=']]

    if check_template(tokens_lists, template_0)
      token_list = [NumericConstantToken.new('5')]
      @expression = ValueExpressionSet.new(token_list, :scalar)
      @errors << 'TAB() not allowed' if @expression.has_tab
    elsif check_template(tokens_lists, template_1)
      token_lists = split_tokens(tokens_lists[0], false)
      @expression = ValueExpressionSet.new(token_lists[0], :scalar)
      @errors << 'TAB() not allowed' if @expression.has_tab
      @elements = make_references(nil, @expression)
    else
      @errors << 'Syntax error'
    end

    @errors << 'Too many values' if token_lists.size > 1

    @comprehension_effort += @expression.comprehension_effort
  end

  def uncache_core
    @expression.uncache
  end

  def dump
    lines = @expression.dump

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    values = @expression.evaluate(interpreter)
    value = values[0]
    sleep(value.to_v)
  end
end

# STOP
class StopStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('STOP')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)
    @autonext = false unless @any_if_modifiers

    template = []

    @errors << 'Syntax error' unless
      check_template(tokens_lists, template)
  end

  def set_transfers(_)
    @transfers = []

    empty_line_number = LineNumber.new(nil)
    @transfers << TransferRefLine.new(empty_line_number, :stop)
  end

  def dump
    lines = ['']

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    io = interpreter.console_io
    io.newline_when_needed
    interpreter.stop
  end
end

# WRITE
class WriteStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('WRITE')]
    ]
  end

  include FileFunctions
  include WriteFunctions

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      @items = tokens_to_expressions(tokens_lists, :scalar)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @elements = make_references(@items, @file_tokens)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    i = 0
    last_was_carriage = true

    while i < @items.size
      item = @items[i]

      # insert an implicit carriage control
      fhr.print_item(',') unless item.carriage_control? || last_was_carriage

      if item.carriage_control?
        item.write(fhr)
      else
        item.write(fhr, interpreter)
      end

      last_was_carriage = item.carriage_control?

      i += 1
    end
  end
end

# ARR FORGET
class ArrForgetStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR'), KeywordToken.new('FORGET')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      # parse variable
      @variables = []

      tokens_list = split_on_group_separators(tokens_lists[0])
      tokens_list.each do |tokens|
        if tokens[0].variable?
          variable_name = VariableName.new(tokens[0])
          variable = Variable.new(variable_name, :array, [], [])
          @variables << variable
          variablex = XrefEntry.new(variable.to_s, nil, false)
          @elements[:variables] += [variablex]
        else
          @errors << "Invalid variable #{tokens[0]}"
        end
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []

    @variables.each { |variable| lines << variable.dump }

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    @variables.each { |variable| interpreter.forget_compound_values(variable) }
  end
end

# ARR INPUT
class ArrInputStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR'), KeywordToken.new('INPUT')]
    ]
  end

  include FileFunctions
  include InputFunctions

  def initialize(_, keywords, tokens_lists)
    super

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      @items = tokens_to_expressions(tokens_lists, :array, true)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @prompt = extract_prompt(@items)
      @elements = make_references(@items, @file_tokens, @prompt)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :read)

    prompt = nil

    unless @prompt.nil?
      prompts = @prompt.evaluate(interpreter)
      prompt = prompts[0]
    end

    # compute size based on variable dimensions
    # create list of variables with subscripts
    item_names = []

    @items.each do |item|
      targets = item.evaluate(interpreter)
      targets.each do |target|
        name = target.name

        interpreter.set_dimensions(target.name, target.dimensions) if
          target.dimensions?

        raise BASICRuntimeError, :te_arr_no_dim unless
          interpreter.dimensions?(target.name)

        # make sure dimension is one
        dims = interpreter.get_dimensions(name)
        raise(BASICExpressionError, 'Not an array') unless dims.size == 1

        # build names
        base = $options['base'].value
        (base..dims[0].to_i).each do |col|
          coord = AbstractElement.make_coord(col)
          wcoord = interpreter.wrap_subscripts(name, coord)
          variable = Variable.new(name, :array, coord, wcoord)
          item_names << variable
        end
      end
    end

    # get all of the needed values
    if fh.nil?
      # from console
      values = input_values(fhr, interpreter, prompt, item_names.size)
      fhr.implied_newline
    else
      # from file
      values = file_values(fhr, interpreter)
    end

    raise BASICRuntimeError, :te_too_few if values.size < item_names.size

    # use names based on variable dimensions
    name_value_pairs =
      zip(item_names, values[0..item_names.length])

    name_value_pairs.each do |hash|
      variable = hash['name']
      value = hash['value']
      interpreter.set_value(variable, value)
    end

    interpreter.clear_previous_lines
  end
end

# ARR PLOT
class ArrPlotStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR'), KeywordToken.new('PLOT')]
    ]
  end

  include FileFunctions
  include PrintFunctions

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template2 = [[1, '>=']]

    @items = []

    if check_template(tokens_lists, template2)
      items = split_tokens(tokens_lists[0], false)
      @items = tokens_to_expressions_2(items, :array)
      @file_tokens = extract_file_handle(@items)

      @items.each do |item|
        if item.class.to_s == 'ValueExpressionSet' && !%i[numeric
                                                          integer].include?(item.content_type)
          @errors << 'Wrong type'
        end
      end

      @elements = make_references(@items, @file_tokens)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }

      @mccabe = @items.size
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []

    lines += @file_tokens.dump unless @file_tokens.nil?

    @items.each do |item|
      lines += item.dump
    end

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    @items.each do |item|
      if item.carriage_control?
        item.plot(fhr)
      else
        item.plot(fhr, interpreter)
      end
    end
  end
end

# ARR PRINT
class ArrPrintStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR'), KeywordToken.new('PRINT')]
    ]
  end

  include FileFunctions
  include PrintFunctions

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    # build list: exp, cc, exp, cc, 'USING' exp, cc, exp, cc
    tokens = tokens_lists.flatten
    list = split_keywords(tokens)

    @items = []

    if list.empty?
      expressions = tokens_to_expressions([], :array)
      @items << expressions
    else
      list.each do |item|
        if item.class.to_s == 'Array'
          tokens_lists = split_tokens(item, true)
          expressions = tokens_to_expressions(tokens_lists, :array)
          @items << expressions
        else
          @items << item
        end
      end
    end

    # if list first item is expression
    #   extract possible file handle
    @file_tokens = nil
    if !@items.empty? && (@items[0].class.to_s == 'Array') && !@items[0].empty?
      @file_tokens = extract_file_handle(@items[0])
    end

    # end with
    #   @file_tokens : exp or nil
    #   #items : list either expression, cc, or keyword

    # if item is keyword then it must be 'USING'
    @items.each do |item|
      if item.class.to_s != 'Array' && !(item.keyword? && item.to_s == 'USING')
        @errors << 'Syntax error'
      end
    end

    @elements = make_references(nil, @file_tokens)

    @items.each do |item|
      if item.class.to_s == 'Array'
        elements = make_references(item)

        elements.each { |k, v| @elements[k] += v }

        item.each { |it| @comprehension_effort += it.comprehension_effort }
      elsif item.keyword?
        @comprehension_effort += 1
      end
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    j = 0
    while j < @items.size
      item = @items[j]

      if item.class.to_s == 'Array'
        i = 0
        last_was_carriage = true

        while i < item.size
          it = item[i]

          # insert an implicit carriage control
          fhr.implied unless it.carriage_control? || last_was_carriage

          if it.carriage_control?
            it.print(fhr)
          else
            formats = nil
            it.compound_print(fhr, interpreter, formats)
          end

          last_was_carriage = it.carriage_control?

          i += 1
        end
      else
        # item must be 'USING'
        j += 1

        raise BASICRuntimeError, :te_no_fmt if j >= @items.size

        # extract formats
        item = @items[j]

        format_spec, items = extract_format(item, interpreter)

        raise BASICRuntimeError, :te_no_fmt if format_spec.nil?

        # split format
        formats = split_format(format_spec)

        # check formats wants only one item
        count = 0
        formats.each { |format| count += 1 if format.wants_item }

        raise(BASICSyntaxError, 'Too many fields in USING') unless count <= 1

        raise BASICRuntimeError, :te_few_fmt if items.empty?

        i = 0

        # print variable
        item = items[i]
        item.compound_print(fhr, interpreter, formats)
        last_was_carriage = false

        # if next item is carriage, print it
        i += 1

        if i < items.size && items[i].carriage_control?
          item = items[i]
          item.print(fhr)
          last_was_carriage = true
        end

        i += 1

        while i < items.size
          item = items[i]

          # insert an implicit carriage control
          fhr.implied unless item.carriage_control? || last_was_carriage

          if item.carriage_control?
            item.print(fhr)
          else
            formats = nil
            item.compound_print(fhr, interpreter, formats)
          end

          last_was_carriage = item.carriage_control?

          i += 1
        end
      end

      j += 1
    end
  end
end

# ARR READ
class ArrReadStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR'), KeywordToken.new('READ')]
    ]
  end

  include FileFunctions
  include ReadFunctions

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      items = split_tokens(tokens_lists[0], false)
      @items = tokens_to_expressions(items, :array, true)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @elements = make_references(@items, @file_tokens)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }

      @mccabe += @items.size
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    ds = interpreter.get_data_store(fh)

    @items.each do |item|
      targets = item.evaluate(interpreter)
      targets.each do |target|
        interpreter.set_dimensions(target.name, target.dimensions) if
          target.dimensions?

        raise BASICRuntimeError, :te_arr_no_dim unless
          interpreter.dimensions?(target.name)

        read_values(target.name, interpreter, ds)
      end
    end

    interpreter.clear_previous_lines
  end

  private

  def read_values(name, interpreter, ds)
    dims = interpreter.get_dimensions(name)

    case dims.size
    when 1
      read_array(name, dims, interpreter, ds)
    else
      raise(BASICSyntaxError, 'Dimensions for ARR READ must be 1')
    end
  end

  def read_array(name, dims, interpreter, ds)
    values = {}

    base = $options['base'].value
    (base..dims[0].to_i).each do |col|
      coord = AbstractElement.make_coord(col)
      values[coord] = ds.read
    end

    interpreter.set_values(name, values)
  end
end

# ARR WRITE
class ArrWriteStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR'), KeywordToken.new('WRITE')]
    ]
  end

  include FileFunctions
  include WriteFunctions

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      @items = tokens_to_expressions(tokens_lists, :array)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @elements = make_references(@items, @file_tokens)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    i = 0
    last_was_carriage = true

    while i < @items.size
      item = @items[i]

      # insert an implicit carriage control
      fhr.print_item(',') unless item.carriage_control? || last_was_carriage

      if item.carriage_control?
        item.write(fhr)
      else
        item.write(fhr, interpreter)
      end

      last_was_carriage = item.carriage_control?

      i += 1
    end
  end
end

# ARR assignment
class ArrLetStatement < AbstractLetStatement
  def self.lead_keywords
    [
      [KeywordToken.new('ARR')],
      [KeywordToken.new('ARR'), KeywordToken.new('LET')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[3, '>=']]

    if check_template(tokens_lists, template)
      begin
        @assignment = Assignment.new(tokens_lists[0], :array)

        if @assignment.count_target.zero?
          @errors << 'Assignment must have left-hand value(s)'
        end

        if @assignment.count_value.zero?
          @errors << 'Assignment must have right-hand value(s)'
        end

        @errors << 'TAB() not allowed' if @assignment.has_tab

        @warnings << 'Extra values ignored' if
          @assignment.count_value > @assignment.count_target

        @elements = make_references(nil, @assignment)

        @comprehension_effort += @assignment.comprehension_effort
      rescue BASICExpressionError => e
        @errors << e.message
        @assignment = @rest
      end
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    l_values = @assignment.eval_target(interpreter)
    l_value0 = l_values[0]
    l_dims = interpreter.get_dimensions(l_value0.name)

    interpreter.set_default_args('CON1', l_dims)
    interpreter.set_default_args('CON1%', l_dims)
    interpreter.set_default_args('CON1$', l_dims)
    interpreter.set_default_args('RND1', l_dims)
    interpreter.set_default_args('RND1%', l_dims)
    interpreter.set_default_args('RND1$', l_dims)
    interpreter.set_default_args('ZER1', l_dims)
    interpreter.set_default_args('ZER1%', l_dims)
    interpreter.set_default_args('ZER1$', l_dims)

    r_value = first_value(interpreter)

    interpreter.set_default_args('CON1', nil)
    interpreter.set_default_args('CON1%', nil)
    interpreter.set_default_args('CON1$', nil)
    interpreter.set_default_args('RND1', nil)
    interpreter.set_default_args('RND1%', nil)
    interpreter.set_default_args('RND1$', nil)
    interpreter.set_default_args('ZER1', nil)
    interpreter.set_default_args('ZER1%', nil)
    interpreter.set_default_args('ZER1$', nil)

    r_dims = r_value.dimensions

    values = r_value.values_1

    l_values.each do |l_value|
      interpreter.set_dimensions(l_value, r_dims)
      interpreter.set_values(l_value.name, values)
    end
  end

  private

  def first_target(interpreter)
    l_values = @assignment.eval_target(interpreter)

    l_values[0]
  end

  def first_value(interpreter)
    r_values = @assignment.eval_value(interpreter)
    r_value = r_values[0]

    raise(BASICSyntaxError, 'Expected Array') if
      r_value.class.to_s != 'BASICArray'

    r_value
  end
end

# MAT FORGET
class MatForgetStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT'), KeywordToken.new('FORGET')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      # parse variable
      @variables = []

      tokens_list = split_on_group_separators(tokens_lists[0])
      tokens_list.each do |tokens|
        if tokens[0].variable?
          variable_name = VariableName.new(tokens[0])
          variable = Variable.new(variable_name, :matrix, [], [])
          @variables << variable
          variablex = XrefEntry.new(variable.to_s, nil, false)
          @elements[:variables] += [variablex]
        else
          @errors << "Invalid variable #{tokens[0]}"
        end
      end
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []

    @variables.each { |variable| lines << variable.dump }

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    @variables.each { |variable| interpreter.forget_compound_values(variable) }
  end
end

# MAT INPUT
class MatInputStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT'), KeywordToken.new('INPUT')]
    ]
  end

  include FileFunctions
  include InputFunctions

  def initialize(_, keywords, tokens_lists)
    super

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      @items = tokens_to_expressions(tokens_lists, :array, true)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @prompt = extract_prompt(@items)
      @elements = make_references(@items, @file_tokens, @prompt)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :read)

    prompt = nil

    unless @prompt.nil?
      prompts = @prompt.evaluate(interpreter)
      prompt = prompts[0]
    end

    # compute size based on variable dimensions
    # create list of variables with subscripts
    item_names = []

    @items.each do |item|
      targets = item.evaluate(interpreter)
      targets.each do |target|
        name = target.name

        interpreter.set_dimensions(target.name, target.dimensions) if
          target.dimensions?

        raise BASICRuntimeError, :te_mat_no_dim unless
          interpreter.dimensions?(target.name)

        # make sure dimension is one or two
        dims = interpreter.get_dimensions(name)
        raise(BASICExpressionError, 'Not an array') unless
          dims.size == 1 || dims.size == 2

        # build names
        if dims.size == 1
          base = $options['base'].value
          (base..dims[0].to_i).each do |col|
            coord = AbstractElement.make_coord(col)
            wcoord = interpreter.wrap_subscripts(name, coord)
            variable = Variable.new(name, :matrix, coord, wcoord)
            item_names << variable
          end
        end

        next unless dims.size == 2

        base = $options['base'].value
        (base..dims[0].to_i).each do |row|
          (base..dims[1].to_i).each do |col|
            coords = AbstractElement.make_coords(row, col)
            wcoords = interpreter.wrap_subscripts(name, coords)
            variable = Variable.new(name, :matrix, coords, wcoords)
            item_names << variable
          end
        end
      end
    end

    # get all of the needed values
    if fh.nil?
      # from console
      values = input_values(fhr, interpreter, prompt, item_names.size)
      fhr.implied_newline
    else
      # from file
      values = file_values(fhr, interpreter)
    end

    raise BASICRuntimeError, :te_too_few if values.size < item_names.size

    # use names based on variable dimensions
    name_value_pairs =
      zip(item_names, values[0..item_names.length])

    name_value_pairs.each do |hash|
      variable = hash['name']
      value = hash['value']
      interpreter.set_value(variable, value)
    end

    interpreter.clear_previous_lines
  end
end

# MAT PLOT
class MatPlotStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT'), KeywordToken.new('PLOT')]
    ]
  end

  include FileFunctions
  include PrintFunctions

  def initialize(_, keywords, tokens_lists)
    super

    template2 = [[1, '>=']]

    @items = []

    if check_template(tokens_lists, template2)
      items = split_tokens(tokens_lists[0], false)
      @items = tokens_to_expressions_2(items, :matrix)
      @file_tokens = extract_file_handle(@items)

      @items.each do |item|
        if item.class.to_s == 'ValueExpressionSet' && !%i[numeric
                                                          integer].include?(item.content_type)
          @errors << 'Wrong type'
        end
      end

      @elements = make_references(@items, @file_tokens)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }

      @mccabe = @items.size
    else
      @errors << 'Syntax error'
    end
  end

  def dump
    lines = []

    lines += @file_tokens.dump unless @file_tokens.nil?

    @items.each do |item|
      lines += item.dump
    end

    @modifiers&.each { |item| lines += item.dump }

    lines
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    @items.each do |item|
      if item.carriage_control?
        item.plot(fhr)
      else
        item.plot(fhr, interpreter)
      end
    end
  end
end

# MAT PRINT
class MatPrintStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT'), KeywordToken.new('PRINT')]
    ]
  end

  include FileFunctions
  include PrintFunctions

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    # build list: exp, cc, exp, cc, 'USING' exp, cc, exp, cc
    tokens = tokens_lists.flatten
    list = split_keywords(tokens)

    @items = []

    if list.empty?
      expressions = tokens_to_expressions([], :matrix)
      @items << expressions
    else
      list.each do |item|
        if item.class.to_s == 'Array'
          tokens_lists = split_tokens(item, true)
          expressions = tokens_to_expressions(tokens_lists, :matrix)
          @items << expressions
        else
          @items << item
        end
      end
    end

    # if list first item is expression
    #   extract possible file handle
    @file_tokens = nil
    if !@items.empty? && (@items[0].class.to_s == 'Array') && !@items[0].empty?
      @file_tokens = extract_file_handle(@items[0])
    end

    # end with
    #   @file_tokens : exp or nil
    #   @items : list either expression, cc, or keyword

    # if item is keyword then it must be 'USING'
    @items.each do |item|
      if item.class.to_s != 'Array' && !(item.keyword? && item.to_s == 'USING')
        @errors << 'Syntax error'
      end
    end

    @elements = make_references(nil, @file_tokens)

    @items.each do |item|
      if item.class.to_s == 'Array'
        elements = make_references(item)

        elements.each { |k, v| @elements[k] += v }

        item.each { |it| @comprehension_effort += it.comprehension_effort }
      elsif item.keyword?
        @comprehension_effort += 1
      end
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    j = 0
    while j < @items.size
      item = @items[j]

      if item.class.to_s == 'Array'
        i = 0
        last_was_carriage = true

        while i < item.size
          it = item[i]

          # insert an implicit carriage control
          fhr.implied unless it.carriage_control? || last_was_carriage

          if it.carriage_control?
            # MAT PRINT has different operations for carriage controls
            carriage = map_carriage(it)
            carriage.print(fhr)
          else
            formats = nil
            it.compound_print(fhr, interpreter, formats)
          end

          last_was_carriage = it.carriage_control?

          i += 1
        end
      else
        # item must be 'USING'
        j += 1

        raise BASICRuntimeError, :te_no_fmt if j >= @items.size

        # extract formats
        item = @items[j]

        format_spec, items = extract_format(item, interpreter)

        raise BASICRuntimeError, :te_no_fmt if format_spec.nil?

        # split format
        formats = split_format(format_spec)

        # check formats wants only one item
        count = 0
        formats.each { |format| count += 1 if format.wants_item }

        raise(BASICSyntaxError, 'Too many fields in USING') unless count <= 1

        raise BASICRuntimeError, :te_few_fmt if items.empty?

        i = 0

        # print variable
        item = items[i]
        item.compound_print(fhr, interpreter, formats)
        last_was_carriage = false

        # if next item is carriage, print it
        i += 1

        if i < items.size && items[i].carriage_control?
          item = items[i]
          # MAT PRINT has different operations for carriage controls
          carriage = map_carriage(item)
          carriage.print(fhr)
          last_was_carriage = true
        end

        i += 1

        while i < items.size
          item = items[i]

          # insert an implicit carriage control
          fhr.implied unless item.carriage_control? || last_was_carriage

          if item.carriage_control?
            # MAT PRINT has different operations for carriage controls
            carriage = map_carriage(item)
            carriage.print(fhr)
          else
            formats = nil
            item.compound_print(fhr, interpreter, formats)
          end

          last_was_carriage = item.carriage_control?

          i += 1
        end
      end

      j += 1
    end
  end

  def map_carriage(it)
    carriage = CarriageControl.new('')

    case it.to_s
    when ', '
      # a comma prints a newline
      carriage = CarriageControl.new('NL')
    when '; '
      # a semi does nothing, even after numerics
      carriage = CarriageControl.new('')
    when ''
      # a newline prints a newline (which is normal)
      carriage = it
    when ' '
      # an implied carriage control does nothing
      carriage = CarriageControl.new('')
    end

    carriage
  end
end

# MAT READ
class MatReadStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT'), KeywordToken.new('READ')]
    ]
  end

  include FileFunctions
  include ReadFunctions

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      items = split_tokens(tokens_lists[0], false)
      @items = tokens_to_expressions(items, :matrix, true)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @elements = make_references(@items, @file_tokens)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }

      @mccabe += @items.size
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    ds = interpreter.get_data_store(fh)

    @items.each do |item|
      targets = item.evaluate(interpreter)
      targets.each do |target|
        interpreter.set_dimensions(target.name, target.dimensions) if
          target.dimensions?

        raise BASICRuntimeError, :te_mat_no_dim unless
          interpreter.dimensions?(target.name)

        read_values(target.name, interpreter, ds)
      end
    end

    interpreter.clear_previous_lines
  end

  private

  def read_values(name, interpreter, ds)
    dims = interpreter.get_dimensions(name)

    case dims.size
    when 1
      read_vector(name, dims, interpreter, ds)
    when 2
      read_matrix(name, dims, interpreter, ds)
    else
      raise(BASICSyntaxError, 'Dimensions for MAT READ must be 1 or 2')
    end
  end

  def read_vector(name, dims, interpreter, ds)
    values = {}

    base = $options['base'].value

    (base..dims[0].to_i).each do |col|
      coord = AbstractElement.make_coord(col)
      values[coord] = ds.read
    end

    interpreter.set_values(name, values)
  end

  def read_matrix(name, dims, interpreter, ds)
    values = {}

    base = $options['base'].value

    (base..dims[0].to_i).each do |row|
      (base..dims[1].to_i).each do |col|
        coords = AbstractElement.make_coords(row, col)
        values[coords] = ds.read
      end
    end

    interpreter.set_values(name, values)
  end
end

# MAT WRITE
class MatWriteStatement < AbstractStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT'), KeywordToken.new('WRITE')]
    ]
  end

  include FileFunctions
  include WriteFunctions

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[1, '>=']]

    if check_template(tokens_lists, template)
      tokens_lists = split_tokens(tokens_lists[0], true)
      @items = tokens_to_expressions(tokens_lists, :matrix)

      @items.each do |item|
        @errors << 'TAB() not allowed' if item.has_tab
      end

      @file_tokens = extract_file_handle(@items)
      @elements = make_references(@items, @file_tokens)

      @items.each { |item| @comprehension_effort += item.comprehension_effort }
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    fh = get_file_handle(interpreter, @file_tokens)
    fhr = interpreter.get_file_handler(fh, :print)

    i = 0
    last_was_carriage = true

    while i < @items.size
      item = @items[i]

      # insert an implicit carriage control
      fhr.print_item(',') unless item.carriage_control? || last_was_carriage

      if item.carriage_control?
        item.write(fhr)
      else
        item.write(fhr, interpreter)
      end

      last_was_carriage = item.carriage_control?

      i += 1
    end
  end
end

# MAT assignment
class MatLetStatement < AbstractLetStatement
  def self.lead_keywords
    [
      [KeywordToken.new('MAT')],
      [KeywordToken.new('MAT'), KeywordToken.new('LET')]
    ]
  end

  def initialize(_, keywords, tokens_lists)
    super

    extract_modifiers(tokens_lists)

    template = [[3, '>=']]

    if check_template(tokens_lists, template)
      begin
        @assignment = Assignment.new(tokens_lists[0], :matrix)

        if @assignment.count_target.zero?
          @errors << 'Assignment must have left-hand value(s)'
        end

        if @assignment.count_value.zero?
          @errors << 'Assignment must have right-hand value(s)'
        end

        @errors << 'TAB() not allowed' if @assignment.has_tab

        @warnings << 'Extra values ignored' if
          @assignment.count_value > @assignment.count_target

        @elements = make_references(nil, @assignment)

        @comprehension_effort += @assignment.comprehension_effort
      rescue BASICRuntimeError => e
        @errors << e.message
        @assignment = @rest
      end
    else
      @errors << 'Syntax error'
    end
  end

  def execute_core(interpreter)
    l_values = @assignment.eval_target(interpreter)
    l_value0 = l_values[0]
    l_dims = interpreter.get_dimensions(l_value0.name)

    interpreter.set_default_args('CON', l_dims)
    interpreter.set_default_args('CON2', l_dims)
    interpreter.set_default_args('CON2%', l_dims)
    interpreter.set_default_args('CON2$', l_dims)
    interpreter.set_default_args('IDN', l_dims)
    interpreter.set_default_args('RND2', l_dims)
    interpreter.set_default_args('RND2%', l_dims)
    interpreter.set_default_args('RND2$', l_dims)
    interpreter.set_default_args('ZER', l_dims)
    interpreter.set_default_args('ZER2', l_dims)
    interpreter.set_default_args('ZER2%', l_dims)
    interpreter.set_default_args('ZER2$', l_dims)

    r_value = first_value(interpreter)

    interpreter.set_default_args('CON', nil)
    interpreter.set_default_args('CON2', nil)
    interpreter.set_default_args('CON2%', nil)
    interpreter.set_default_args('CON2$', nil)
    interpreter.set_default_args('IDN', nil)
    interpreter.set_default_args('RND2', nil)
    interpreter.set_default_args('RND2%', nil)
    interpreter.set_default_args('RND2$', nil)
    interpreter.set_default_args('ZER', nil)
    interpreter.set_default_args('ZER2', nil)
    interpreter.set_default_args('ZER2%', nil)
    interpreter.set_default_args('ZER2$', nil)

    r_dims = r_value.dimensions

    values = r_value.values_1 if r_dims.size == 1
    values = r_value.values_2 if r_dims.size == 2

    l_values.each do |l_value|
      interpreter.set_dimensions(l_value, r_dims)
      interpreter.set_values(l_value.name, values)
    end
  end

  def first_value(interpreter)
    r_values = @assignment.eval_value(interpreter)
    r_value = r_values[0]

    raise(BASICSyntaxError, 'Expected Matrix') if
      r_value.class.to_s != 'Matrix'

    r_value
  end
end
