##### cpp min system2   tools
```

winget install MSYS2.MSYS2

& "C:\msys64\usr\bin\bash.exe" -lc "pacman -Syu --noconfirm"

& "C:\msys64\usr\bin\bash.exe" -lc "pacman -S --noconfirm mingw-w64-ucrt-x86_64-gcc"

```


##### REA agents

```
rea analyze .\native_test.exe --provider ghidra binary_overview
rea instructions .\native_test.exe --provider ghidra --procedure=get_secret_message

```