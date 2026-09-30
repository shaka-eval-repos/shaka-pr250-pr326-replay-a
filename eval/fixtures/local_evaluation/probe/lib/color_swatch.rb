module ColorSwatch
  def self.label(hex)
    value = hex.delete_prefix('#')
    raise ArgumentError, 'expected six hexadecimal digits' unless /\A[0-9a-f]{6}\z/i.match?(value)

    "##{value.upcase}"
  end
end
