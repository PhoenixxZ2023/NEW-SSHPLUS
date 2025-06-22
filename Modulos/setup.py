#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from setuptools import setup, find_packages

# Importa do novo nome da pasta
import xray_util

with open("README.md", "r", encoding='UTF-8') as fh:
    long_description = fh.read()

setup(
    # Nome do pacote para o pip
    name='xray-util',
    # Pega a versão a partir do novo nome
    version=xray_util.__version__,
    description="uma ferramenta para gerenciar a configuração do xray", # Descrição atualizada
    long_description=long_description,
    long_description_content_type="text/markdown",
    keywords='python xray vless trojan xtls reality', # Keywords atualizadas
    # Seus dados de autor (opcional)
    author='PhoenixxZ2023', # Seu nome
    author_email='seu-email@exemplo.com',
    url='https://github.com/PhoenixxZ2023/NEW-SSHPLUS', # URL do seu repositório
    license='GPL',
    packages=find_packages(),
    include_package_data=True,
    zip_safe=False,
    python_requires='>=3',
    entry_points={
        'console_scripts': [
            # Cria o comando 'xray-util' que aponta para a função 'menu' no 'main.py' dentro da nova pasta
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
