/// NotebookLM measures a spreadsheet source in tokens, and the ceiling for that
/// kind of source is far lower than the 500,000-word limit that applies to
/// documents — around 100,000 tokens. A CSV well under the word limit is
/// rejected once it crosses it, which is why large sheets have to be split.
const int defaultTokenBudget = 100000;

/// The character counts a token estimate is built from.
///
/// Splitting accumulates these rather than a per-row token count: rounding
/// every row up to a whole token would over-count a long sheet by hundreds of
/// tokens, cutting each file short and spending more of the notebook's source
/// allowance than the data needs.
class TokenCost {
  const TokenCost(this.myanmar, this.other);

  /// Characters in the Myanmar blocks.
  final int myanmar;

  /// Everything else.
  final int other;

  int get tokens => tokensFor(myanmar, other);

  TokenCost operator +(TokenCost b) =>
      TokenCost(myanmar + b.myanmar, other + b.other);

  static const zero = TokenCost(0, 0);
}

/// Measures [text] for the token estimate.
///
/// Latin text and digits average about four characters per token. Myanmar
/// script does not: it is outside the tokenizer's dense vocabulary and costs
/// roughly a token per character, so a Burmese ledger reaches the ceiling at a
/// fraction of the byte size of an English one. Counting the two separately
/// keeps the split points honest for both.
TokenCost measureTokens(String text) {
  var myanmar = 0;
  for (final unit in text.codeUnits) {
    if ((unit >= 0x1000 && unit <= 0x109F) || (unit >= 0xAA60 && unit <= 0xAA7F)) {
      myanmar++;
    }
  }
  return TokenCost(myanmar, text.length - myanmar);
}

int tokensFor(int myanmar, int other) => myanmar + (other / 4).ceil();

/// Estimated tokens for a whole string.
int estimateTokens(String text) => measureTokens(text).tokens;
