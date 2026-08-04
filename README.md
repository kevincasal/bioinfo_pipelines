# Pipeline de Automatización Bioinformática y Configuración de Entornos - INSPI

## Descripción General
Este repositorio contiene los scripts de automatización, guías y protocolos desarrollados para el **Instituto Nacional de Investigación en Salud Pública (INSPI)**. El objetivo principal es estandarizar, agilizar y asegurar la reproducibilidad en la instalación y gestión de herramientas bioinformáticas empleadas en el análisis, ensamblaje, caracterización y anotación de genomas.

---

## Autoría y Créditos
* **Autor Principàl / Desarrollador:** [Kevin Josue Casal Arroyo]
* **Filiación / Departamento:** [Coordinación Zonal 9-INSPI]
* **Institución:** Instituto Nacional de Investigación en Salud Pública (INSPI)
* **Correo de Contacto:** [kevincasal0@gmail.com]

---

## Estructura del Repositorio

```text
inspi-bioinfo-pipelines/
├── README.md                 # Documentación principal del proyecto
├── LICENSE                   # Licencia de derechos de autor y términos de uso
└── scripts/
    └── setup_bioinfo_env.sh  # Script de despliegue automatizado de Miniconda y entornos

---

## __Módulos y Herramientas Automatizadas 
El script principal de aprovisionamiento (scripts/setup_bioinfo_env.sh) despliega entornos de Conda aislados de manera independiente para evitar el conflicto de dependencias:
Entorno (env)                             Herramienta Bioinformática                    Aplicación Principal
fastqc_env                                FastQC                                        Control de calidad de lecturas de secuenciación bruta
multiqc_env                               MultiQC                                       Agregación de reportes de análisis de múltiples muestras
kraken2_env                               Kraken2                                       Clasificación taxonómica rápida de secuencias
shovill_bacterias_env                     Shovill                                       Ensamblaje genómico optimizado para genomas bacterianos
spades_env                                SPAdes                                        Ensamblador de genomas de novo
quast_env                                 QUAST                                         Evaluación de métricas y calidad de ensamblajes de genomas
prokka_env                                Prokka                                        Anotación rápida de genomas bacterianos.

---

## Requisitos de Sistema

Sistema Operativo: Ubuntu Linux (18.04 LTS, 20.04 LTS, 22.04 LTS o superior).
Conexión a Internet: Requerida para la descarga de paquetes desde los canales bioconda y conda-forge.
Permisos: Usuario con permisos de ejecución en la terminal.

---

## Guía Rápida de Uso

1. Clonar o descargar este repositorio:

    git clone [https://github.com/tu-usuario/bioinfo-pipelines.git](https://github.com/tu-usuario/bioinfo-pipelines.git)
    cd bioinfo-pipelines

2. Otorgar permisos de ejecución al script:
    
    chmod +x scripts/setup_bioinfo_env.sh

3. Ejecutar el script de despliegue:
    ./scripts/setup_bioinfo_env.sh

4. Cargar los cambios en la terminal:
    source ~/.bashrc

5. Verificar entornos creados:
    conda env list

## Licencia y Derechos de Autor
Este proyecto está protegido bajo los términos especificados en el archivo LICENSE.
© 2026 [Kevin Josue Casal Arroyo]. Todos los derechos reservados.
