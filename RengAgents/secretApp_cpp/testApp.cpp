#include <iostream>
#include <string>

int add_numbers(int a, int b) {
    return a + b;
}

std::string get_secret_message() {
    return "Hello from native code!";
}

int check_license(int code) {
    if (code == 1337) {
        return 1; // valid
    } else if (code % 7 == 0) {
        return 2; // special case
    }
    return 0; // invalid
}

int main() {
    std::cout << get_secret_message() << std::endl;

    int sum = add_numbers(3, 4);
    std::cout << "3 + 4 = " << sum << std::endl;

    int result = check_license(1337);
    std::cout << "License check (1337): " << result << std::endl;

    result = check_license(14);
    std::cout << "License check (14): " << result << std::endl;

    result = check_license(5);
    std::cout << "License check (5): " << result << std::endl;

    return 0;
}