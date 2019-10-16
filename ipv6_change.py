import re, subprocess

result = subprocess.run(['ifconfig', 'he-ipv6'], stdout=subprocess.PIPE)
result = re.findall(r"inet6 (\w+:\w+:\w+:\w+).+<global>", result.stdout.decode('utf-8'))
ipv6_prefix = result[0]

def random_part():
    random_hex = ""
    for i in range(4):
        random_hex = random_hex + ":" + str(subprocess.run(['openssl', 'rand', '-hex', '2'], stdout=subprocess.PIPE).stdout.decode('utf-8')).strip('\n')
    return random_hex

new_ipv6 = ipv6_prefix + random_part()

subprocess.run(['cp', '/etc/network/interfaces', '/etc/network/interfaces.old'], stdout=subprocess.PIPE)
with open("/etc/network/interfaces.old", "r") as fin:
    with open("/etc/network/interfaces", "w") as fout:
        content = fin.read()
        replace_val = r"\1 " + new_ipv6
        new_content = re.sub(r"(address).+", replace_val, content)
        fout.write(new_content)
subprocess.run(['ifdown', 'he-ipv6'], stdout=subprocess.PIPE)
subprocess.run(['ifup', 'he-ipv6'], stdout=subprocess.PIPE)
print("new ipv6 address is", new_ipv6)
