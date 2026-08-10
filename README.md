# ProkFinder

Uma pipeline para busca, recuperação e curagem de genomas de procariotos baseado em dados fenotípicos e metabólicos

O workflow para download pode ser dividido nas seguintes etapas:

1) Seleção dos genomas de acordo com dados do assembly,
taxônomico e/ou fenotípico

texto texto texto texto texto
texto texto texto texto texto
texto texto texto texto texto

2) Filtragem por qualidade

Para remoção de genomas fragmentados e/ou incompletos é feito
uma filtragem diferentes parâmetros de qualidade :
- N° de contigs
- N50
- Cobertura
- N° de gaps (bases 'N')
- Completude e Contaminacao

Dentre eles, o n° de contigs, N50 e gaps são calculados pelo
SeqKit v.; a cobertura é obtida dos metadados do assembly; a 
completude e contaminacao sao calculadas pelo CheckM2 V.

3) Classificao taxonômica

Aos genomas que ja possuem uma classificacao taxonomica definida
no GTDB, a classificacao é dada por uma simples busca nas tabelas
do proprio GTDB da ultima (Ex: 2026 - Release 232)
- ar53_taxonomy.tsv 
- bac120_taxonomy.tsv

Porém como os genomas são baixados do NCBI, nem todos eles possuem
uma classificacao taxonômica do GTDB. Por isso, opcionalmente, pode
ser realizada uma classificacao com os genomas remanescentes utilizando
o GTDB-TK v.

[IMPORTANTE] O GTDB-TK demanda uma quantidade grande de memoria RAM
para permitir o carregamento das arvores filogeneticas. É recomendado
que a execução seja feita em cluster de alto desempenho (HPC)
utilizando, no minimo, XXXX GB de RAM.

Os ranks taxônomicos dos genomas são então utilizados para organiza-los
em diretorios, sendo que os genomas são inseridos dentro do dir referente
ao rank taxonômico mais baixo:

d__Bacteria
└── p__Bacillota
    └── c__Bacilli
        └── o__Bacillales
            └── f__Bacillaceae
                └── g__Geobacillus
                    ├── GCA_12345677.1
                    ├── GCA_12345678.1
                    └── GCA_12345679.1

4) Desreplicao dos genomas

Realiza-se a desreplicacao dos genomas usando o skDER v. para 
remoção de genomas redundantes e diminuicao de vieses de
amostragem e sequenciamento

A desreplicacao é feita entre genomas dos niveis taxonomicos mais
baixos (ex: especies, genero) e os resultados sao inseridos, dentro 
da propria estrutura de diretorios

└── g__Geobacillus
    ├── GCA_12345679.1
    └── Representative_Genomes
        ├── GCA_12345677.1
        └── GCA_12345678.1

Opcionalmente, o skDER oferece a opcao de remover temporariamente 
os elementos geneticos moveis (MGE) dos genomas, permitindo uma 
desreplicacao mais justa entre os genomas de mesmo taxon. Os MGEs 
podem ser filtrados utilizando alguma das duas ferramentas:

- PhiSpy v. (localiza profagos apenas, mais rapido)
- geNOMAD (localiza profagos e plasmideos, mais lento)

Nessa caso, os resultados gerados conteram tambem informacoes sobre os
MGE identificados. Exemplo utilizando o PhiSpy:

└── Representative_Genomes
	├── GCA_12345677.1
	├── GCA_12345678.1
	└── SKDER-RESULTS
		├── mgecut_processed_genomes
		│   ├── GCA_12345677.1
		│   └── GCA_12345678.1
		└── mgecut_tmp
			└── GCA_12345677.1
				├── GCA_12345677.1.fna
				└── PhiSpy_Results
					├── Sample.gbk
					├── phispy.log
					└── prophage_coordinates.tsv

5) Obtencao dos resultados


texto texto texto texto texto
texto texto texto texto texto
texto texto texto texto texto

1) Provide a list of Acession Number frm GenBank or RefSeq in a .tsv file
2) Let the pipeline select your genomes based on:
- Isolation Source: recommend for finding genomes from enviromental samples.
Ex: metagenome-derived-genomes (MAG)
- List of TaxID or Taxon Names: recommend for finding genomes from already
described species or taxons in literature
- Other traits: Assembly Info, Assembly Quality, Phenotypic Traits
2.1) You can also use the search_genomes command in a pipe with download_wf:
Ex: prokfinden search_genomes --temp-min 45 | download_wf 
(command for downloading all prokatyotes genomes from strains that have a
optimum growth temperature of 45°C or higher)
3) Other traits: same options as search_genomes to select genomes