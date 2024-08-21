# Local multimodal LLM evaluation

Evaluating different models and their quantizations in terms of accuracy and speed. This repository utilizes the [MS COCO](https://cocodataset.org) dataset and API to track the following criteria on a captioning task:

* Bleu 1-4
* METEOR
* ROUGE-L
* CIDEr
* SPICE

The project `llama.cpp` is used as CLI programs, rather than a library. This is subject to change.

## Prerequisites

For full functionality of the notebook, the following is required:

* A Unix operating system
* [Anaconda](https://www.anaconda.com/) package manager
* [Git LFS](https://git-lfs.com/) extension
* About 100 GB of free space

To browse a DataFrame with results loaded from a CSV file, only Pandas and a notebook engine are needed.

> [!NOTE]
> The following alternatives are currently not tested and do not include installation guide:
> * For Windows, Cygwin may be sufficient, alternatively consider using WSL
> * All used packages should exist on pip, see the dependencies section of conda-env.yml
> * Spyder IDE and Spyder Notebook can be replaced with Jupyter Notebook
> * If disk space is an issue, consider manually deleting large files and .git folders from model repos

## Setup

With Anaconda installed, create a new environment with:

```
conda env create -f conda-env.yml
```

> [!NOTE]
> * Use `-n NAME` if you already have an Anaconda environment by the name "llama"
> * Alternatively, `conda-env-full.yml` contains a fully specified dependency dump

## Usage

The notebook `model-eval.ipynb` contains all further setup, experiments and result visualizations.

Experiment results are saved and can be loaded into the visualizations portion of the notebook without the prerequisites needed to run the experiments.

## Useful links

Working with notebooks in Spyder: [Spyder Notebook Documentation](https://docs.spyder-ide.org/current/plugins/notebook.html)
