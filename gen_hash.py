import hashlib
import base64
import os
import sys

def generate(password: str, iterations: int = 210000) -> str:
    salt = os.urandom(16)
    derived = hashlib.pbkdf2_hmac(
        'sha256',
        password.encode('utf-8'),
        salt,
        iterations,
        dklen=32,
    )
    salt_b64 = base64.b64encode(salt).decode('ascii')
    hash_b64 = base64.b64encode(derived).decode('ascii')
    return f"pbkdf2-sha256:{iterations}:{salt_b64}:{hash_b64}"

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Penggunaan: python gen_hash.py <password>")
        sys.exit(1)
    print(generate(sys.argv[1]))