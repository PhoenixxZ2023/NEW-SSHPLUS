#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from setuptools import setup, find_packages

import xray_util

try:
    with open("README.md", "r", encoding='UTF-8') as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Painel Xray personalizado por PhoenixxZ2023"

setup(
    name='xray-util',
    version=xray_util.__version__,
    description="uma ferramenta para gerenciar a configuração do xray",
    long_description=long_description,
    long_description_content_type="text/markdown",
    keywords='python xray vless trojan xtls reality',
    author='PhoenixxZ2023',
    author_email='seu-email@exemplo.com',
    url='https://github.com/PhoenixxZ2023/NEW-SSHPLUS',
    license='GPL',
    packages=find_packages(),
    
    # Esta linha diz ao setup para procurar e usar o arquivo MANIFEST.in
    include_package_data=True,
    
    zip_safe=False,
    python_requires='>=3',
    entry_points={
        'console_scripts': [
            'xray-util = xray_util.main:menu'
        ]
    },
    classifiers=[
        'Topic :: Utilities',
        'Development Status :: 5 - Production/Stable',
        "License :: OSI Approved :: GNU General Public License v3 (GPLv3)",
        "Natural Language :: English",
        'Natural Language :: Chinese (Simplified)',
        'Programming Language :: Python :: 3',
    ]
)
