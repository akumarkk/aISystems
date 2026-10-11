using System;

namespace SecretApp;

class Program
{
    private static string SuperSecretDbKey = "ConnString-XYZ-998844"; // Embedded hardcoded literal

    static void Main(string[] args)
    {
        Console.WriteLine("Application running securely...");
    }
}