#!python3
import os
import requests
from bs4 import BeautifulSoup

# UA used to scrap target.
headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
}

# Root url where we can find the Pfizer Docs.
docs_url = 'https://phmpt.org/pfizer-16-plus-documents/'
print(f"Getting index on   [{docs_url}]")
res = requests.get(docs_url, headers=headers)
res.raise_for_status()

content = res.text
soup = BeautifulSoup(content, 'html.parser')

# Create zip_data directory if it doesn't exist
xpt_path = "xpt_data"
zip_path = "zip_data"
os.makedirs(zip_path, exist_ok=True)

# Downloads each file.
tbody = soup.find('tbody')
trs = tbody.find_all('tr')
for tr in trs:
    tds = tr.find_all('td')
    if not tds:
        continue
    file_name = tds[0].get_text(strip=True).lower()
    file_url = tds[3].find('a')['href']
    online_file = file_url.split('/')[-1]
    file_ext = online_file.split('.')[-1]
    if 'c4591001' in file_name and 'xpt' in file_name:
        local_file = None
        if file_ext == 'zip':
            local_file = f"{zip_path}/{online_file}"
        elif file_ext == 'xpt':
            local_file = f"{xpt_path}/{online_file}"
        else:
            raise ValueError(f"Unknown extension : [{file_ext}] on file [{file_name}] ({online_file}), contact the script authors to obtain an update.")
        if not os.path.isfile(local_file):
            print(f"Downloading [{local_file}] from [{file_url}]")
            res = requests.get(file_url, headers=headers)
            with open(local_file, 'wb') as f:
                f.write(res.content)
