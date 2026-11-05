using System.Security.Cryptography;

namespace Wake.Core;

public sealed class Challenge
{
    private const string Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
    public string Code { get; } = string.Concat(Enumerable.Range(0, 8).Select(_ =>
        Alphabet[RandomNumberGenerator.GetInt32(Alphabet.Length)]));
    public bool TypingPending { get; private set; }
    public int Remaining { get; private set; }
    public int Left { get; private set; }
    public int Right { get; private set; }
    public bool Complete => !TypingPending && Remaining == 0;
    public Challenge(bool typing, int mathCount)
    {
        if (mathCount is < 0 or > 8) throw new ArgumentOutOfRangeException(nameof(mathCount));
        TypingPending = typing;
        Remaining = mathCount;
        NewProblem();
    }
    public bool SubmitCode(string code)
    {
        if (!TypingPending || code != Code) return false;
        TypingPending = false;
        return true;
    }
    public bool SubmitAnswer(int answer)
    {
        if (TypingPending || Remaining == 0 || answer != Left + Right) return false;
        Remaining--;
        if (Remaining > 0) NewProblem();
        return true;
    }
    private void NewProblem() { Left = RandomNumberGenerator.GetInt32(1, 21); Right = RandomNumberGenerator.GetInt32(1, 21); }
}
