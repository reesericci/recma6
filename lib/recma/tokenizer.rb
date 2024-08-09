require 'recma/lexeme'
require 'recma/char_range'
require 'strscan'

module RECMA
  class Tokenizer
    KEYWORDS = %w{
      break case catch continue default delete do else finally for function
      if in instanceof new return switch this throw try typeof var void while
      with

      const true false null debugger
    }

    RESERVED = %w{
      abstract boolean byte char class double enum export extends
      final float goto implements import int interface long native package
      private protected public short static super synchronized throws
      transient volatile
    }

    LITERALS = {
      # Punctuators
      '=='  => :EQEQ,
      '!='  => :NE,
      '===' => :STREQ,
      '!==' => :STRNEQ,
      '<='  => :LE,
      '>='  => :GE,
      '||'  => :OR,
      '&&'  => :AND,
      '++'  => :PLUSPLUS,
      '--'  => :MINUSMINUS,
      '<<'  => :LSHIFT,
      '<<=' => :LSHIFTEQUAL,
      '>>'  => :RSHIFT,
      '>>=' => :RSHIFTEQUAL,
      '>>>' => :URSHIFT,
      '>>>='=> :URSHIFTEQUAL,
      '&='  => :ANDEQUAL,
      '%='  => :MODEQUAL,
      '^='  => :XOREQUAL,
      '|='  => :OREQUAL,
      '+='  => :PLUSEQUAL,
      '-='  => :MINUSEQUAL,
      '*='  => :MULTEQUAL,
      '/='  => :DIVEQUAL,
    }

    # Some keywords can be followed by regular expressions (eg, return and throw).
    # Others can be followed by division.
    KEYWORDS_THAT_IMPLY_DIVISION = %w{
      this true false null
    }

    KEYWORDS_THAT_IMPLY_REGEX = KEYWORDS - KEYWORDS_THAT_IMPLY_DIVISION

    SINGLE_CHARS_THAT_IMPLY_DIVISION = [')', ']', '}']

    def initialize(&block)
      @lexemes = Hash.new {|hash, key| hash[key] = [] }

      token(:COMMENT, /\/(?:\*(?:.)*?\*\/|\/[^\n]*)/m, ['/'])
      token(:STRING, /"(?:[^"\\]*(?:\\.[^"\\]*)*)"|'(?:[^'\\]*(?:\\.[^'\\]*)*)'/m, ["'", '"'])

      # A regexp to match floating point literals (but not integer literals).
      digits = ('0'..'9').to_a
      token(:NUMBER, /\d+\.\d*(?:[eE][-+]?\d+)?|\d+(?:\.\d*)?[eE][-+]?\d+|\.\d+(?:[eE][-+]?\d+)?/m, digits+['.']) do |type, value|
        value.gsub!(/\.(\D)/, '.0\1') if value =~ /\.\w/
        value.gsub!(/\.$/, '.0') if value =~ /\.$/
        value.gsub!(/^\./, '0.') if value =~ /^\./
        [type, eval(value)]
      end
      token(:NUMBER, /0[xX][\da-fA-F]+|0[0-7]*|\d+/, digits) do |type, value|
        [type, eval(value)]
      end

      literal_chars = LITERALS.keys.map {|k| k.slice(0,1) }.uniq
      literal_regex = Regexp.new(LITERALS.keys.sort_by { |x|
          x.length
        }.reverse.map { |x| "#{x.gsub(/([|+*^])/, '\\\\\1')}" }.join('|'))
      token(:LITERALS, literal_regex, literal_chars) do |type, value|
        [LITERALS[value], value]
      end

      word_chars = ('a'..'z').to_a + ('A'..'Z').to_a + ['_', '$']
      token(:RAW_IDENT, /([_\$A-Za-z][_\$0-9A-Za-z]*)/, word_chars) do |type,value|
        if KEYWORDS.include?(value)
          [value.upcase.to_sym, value]
        elsif RESERVED.include?(value)
          [:RESERVED, value]
        else
          [:IDENT, value]
        end
      end

      # To distinguish regular expressions from comments, we require that
      # regular expressions start with a non * character (ie, not look like
      # /*foo*/). Note that we can't depend on the length of the match to
      # correctly distinguish, since `/**/i` is longer if matched as a regular
      # expression than as matched as a comment.
      # Incidentally, we're also not matching empty regular expressions
      # (eg, // and //g). Here we could depend on match length and priority to
      # determine that these are actually comments, but it turns out to be
      # easier to not match them in the first place.
      token(:REGEXP, /\/(?:[^\/\r\n\\*]|\\[^\r\n])[^\/\r\n\\]*(?:\\[^\r\n][^\/\r\n\\]*)*\/[gim]*/, ['/'])
      token(:S, /[\s\r\n]*/m, [" ", "\t", "\r", "\n", "\f"])

      symbols = ('!'..'/').to_a + (':'..'@').to_a + ('['..'^').to_a + ['`'] + ('{'..'~').to_a
      token(:SINGLE_CHAR, /./, symbols) do |type, value|
        [value, value]
      end
    end

    def tokenize(string)
      raw_tokens(string).map { |x| x.to_racc_token }
    end

    def raw_tokens(string)
      scanner = StringScanner.new(string)
      tokens = []
      range = CharRange::EMPTY
      accepting_regexp = true
      while !scanner.eos?
        longest_token = nil

        @lexemes[scanner.peek(1)].each { |lexeme|
          next if lexeme.name == :REGEXP && !accepting_regexp

          match = lexeme.match(scanner)
          next if match.nil?
          longest_token = match if longest_token.nil?
          next if longest_token.value.length >= match.value.length
          longest_token = match
        }

        if longest_token.name != :S
          accepting_regexp = followable_by_regex(longest_token)
        end

        range = range.next(longest_token.value)
        scanner.pos += longest_token.value.length
        longest_token.range = range
        tokens << longest_token
      end
      tokens
    end

    private

    # Registers a lexeme and maps it to all the characters it can
    # begin with.  So later when scanning the source we only need to
    # match those lexemes that can begin with the character we're at.
    def token(name, pattern, chars, &block)
      lexeme = Lexeme.new(name, pattern, &block)
      chars.each do |c|
        @lexemes[c] << lexeme
      end
    end

    def followable_by_regex(current_token)
      case current_token.name
      when :RAW_IDENT
        KEYWORDS_THAT_IMPLY_REGEX.include?(current_token.value)
      when :NUMBER
        false
      when :SINGLE_CHAR
        !SINGLE_CHARS_THAT_IMPLY_DIVISION.include?(current_token.value)
      else
        true
      end
    end
  end
end
