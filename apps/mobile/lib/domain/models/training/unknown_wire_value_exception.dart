/// Ein Wert aus dem Sync, den diese App-Version nicht kennt (z. B. ein neuer
/// Übungstyp). Anders als bei anderen Formatfehlern hilft ein App-Update.
class UnknownWireValueException extends FormatException {
  const UnknownWireValueException(super.message, [super.source]);
}
