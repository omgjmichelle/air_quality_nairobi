
# ---------------------------------------------------------------------------------------
# Initialize DVC
.dvc: | .git
	@dvc init
	@dvc config cache.protected true
	@dvc remote add -d origin $(DVC_BUCKET)
	@git add .dvc/config


# ---------------------------------------------------------------------------------------
# SNIPPET pour initialiser DVC avec la production de fichiers distants dans des buckets
# Voir: https://dvc.org/doc/user-guide/external-outputs
# Use :
# - make dvc-external-s3
# - make dvc-external-gs
# - make dvc-external-azure
# - make dvc-external-ssh
# - make dvc-external-htfs
.PHONY: dvc-external-*
## Initialize the DVC external cache provider (dvc-external-s3)
dvc-external-%: $(REQUIREMENTS) | .dvc
	@dvc remote add ${*}cache $(DVC_BUCKET)/cache
	@dvc config cache.${*} ${*}cache

# ---------------------------------------------------------------------------------------
# SNIPPET pour vérouiller un fichier DVC pour ne plus le reconstruire, meme si cela
# semble nécessaire. C'est util en phase de développement.
# See https://dvc.org/doc/commands-reference/lock
# Lock DVC file
lock-%: $(REQUIREMENTS) | .dvc
	@dvc lock $(*:lock-%=%)

# ---------------------------------------------------------------------------------------
# SNIPPET pour dévérouiller un fichier DVC pour pouvoir le reconstruire.
# See https://dvc.org/doc/commands-reference/unlock
# Lock DVC file
unlock-%: $(REQUIREMENTS) | .dvc
	@dvc unlock $(*:lock-%=%)

# ---------------------------------------------------------------------------------------
# SNIPPET pour afficher les métrics gérées par DVC.
# See https://dvc.org/doc/commands-reference/metrics
## show the DVC metrics
metrics: $(REQUIREMENTS) | .dvc
	@dvc metrics show

# ---------------------------------------------------------------------------------------
# SNIPPET pour supprimer les fichiers de DVC du projet
# Remove all .dvc files
clean-dvc:
	@rm -Rf .dvc
	@-/usr/bin/find . -type f -name "*.dvc" -delete

#################################################################################
# PROJECT RULES                                                                 #
#################################################################################
#
# ┌─────────┐ ┌──────────┐ ┌───────┐ ┌──────────┐ ┌───────────┐
# │ prepare ├─┤ features ├─┤ train ├─┤ evaluate ├─┤ visualize │
# └─────────┘ └──────────┘ └───────┘ └──────────┘ └───────────┘
#

# Meta parameters
# TODO: Ajustez les meta-paramètres
ifdef DEBUG
EPOCHS :=--epochs 1
BATCH_SIZE :=--batch-size 1
else
EPOCHS :=--epochs 10
BATCH_SIZE :=--batch-size 16
endif
SEED :=--seed 12345

.PHONY: prepare features train evaluate visualize

# Rule to declare an implicite dependencies from sub module for all root project files
TOOLS:=$(shell find air_quality_nairobi/ -mindepth 2 -type f -name '*.py')
air_quality_nairobi/*.py : $(TOOLS)
	@touch $@

prepare.dvc \
$(DATA)/interim/datas-prepared.csv: $(REQUIREMENTS) \
    air_quality_nairobi/prepare_dataset.py \
    $(DATA)/raw/*
	dvc run -q -f prepare.dvc \
		--overwrite-dvcfile \
		--ignore-build-cache \
		-d air_quality_nairobi/prepare_dataset.py \
		-d air_quality_nairobi/tools \
		-d $(DATA)/raw/ \
		-o $(DATA)/interim/datas-prepared.csv \
	python -O -m air_quality_nairobi.prepare_dataset \
		$(DATA)/raw/datas.csv \
		$(DATA)/interim/datas-prepared.csv
	git add prepare.dvc
prepare.dvc: $(DATA)/interim/datas-prepared.csv
## Prepare the dataset
prepare: prepare.dvc

features.dvc \
$(DATA)/interim/datas-features.csv : $(REQUIREMENTS) \
    air_quality_nairobi/build_features.py \
    $(DATA)/interim/datas-prepared.csv
	dvc run -q -f features.dvc \
		--overwrite-dvcfile \
		--ignore-build-cache \
		-d air_quality_nairobi/build_features.py \
		-d air_quality_nairobi/tools \
		-d $(DATA)/interim/datas-prepared.csv \
		-o $(DATA)/interim/datas-features.csv \
	python -O -m air_quality_nairobi.build_features \
		$(DATA)/interim/datas-prepared.csv \
		$(DATA)/interim/datas-features.csv
	git add features.dvc
## Add features
features: $(DATA)/interim/datas-features.csv

train.dvc \
models/model.pkl : $(REQUIREMENTS) \
    air_quality_nairobi/train_model.py \
    $(DATA)/interim/datas-features.csv
	dvc run -q -f train.dvc \
		--overwrite-dvcfile \
		--ignore-build-cache \
		-d air_quality_nairobi/train_model.py \
		-d air_quality_nairobi/tools \
		-d $(DATA)/interim/datas-features.csv \
		-o models/model.pkl \
	python -O -m air_quality_nairobi.train_model \
	    $(SEED) \
		$(BATCH_SIZE) \
		$(EPOCHS) \
		$(DATA)/interim/datas-features.csv \
		models/model.pkl
	git add train.dvc
## Train the model
train: models/model.pkl

Dvcfile.dvc \
reports/metric.json: $(REQUIREMENTS) \
    air_quality_nairobi/evaluate_model.py \
    models/model.pkl
	dvc run -q -f Dvcfile.dvc \
		--overwrite-dvcfile \
		--ignore-build-cache \
		-d air_quality_nairobi/evaluate_model.py \
		-d air_quality_nairobi/tools \
		-d models/model.pkl \
		-M reports/metric.json \
	python -O -m air_quality_nairobi.evaluate_model \
		models/model.pkl \
		$(DATA)/interim/datas-features.csv \
		reports/metric.json
	git add Dvcfile.dvc
## Evalutate the model
evaluate: reports/metric.json

## Visualize the result
visualize: $(REQUIREMENTS) \
    air_quality_nairobi/visualize.py \
    models/model.pkl \
    reports/metric.json
	@dvc metrics show
	python -O -m air_quality_nairobi.visualize \
	    reports/


# See https://dvc.org/doc/commands-reference/repro
.PHONY: repro
## 	Re-run commands recorded in the last DVC stages in the same order.
repro: evaluate.dvc
	dvc repro $<


