#################################################################################
# PROJECT RULES                                                                 #
#################################################################################
#
# ┌─────────┐ ┌──────────┐ ┌───────┐ ┌──────────┐ ┌───────────┐
# │ prepare ├─┤ features ├─┤ train ├─┤ evaluate ├─┤ visualize │
# └─────────┘ └──────────┘ └───────┘ └──────────┘ └───────────┘
#

.PHONY: prepare features train evaluate visualize
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

# Rule to declare an implicite dependencies from sub module for all root project files
TOOLS:=$(shell find air_quality_nairobi/ -mindepth 2 -type f -name '*.py')
air_quality_nairobi/*.py : $(TOOLS)
	@touch $@

$(DATA)/interim/datas-prepared.csv : $(REQUIREMENTS) air_quality_nairobi/prepare_dataset.py $(DATA)/raw/*
	@python -O -m air_quality_nairobi.prepare_dataset \
		$(DATA)/raw/datas.csv \
		$(DATA)/interim/datas-prepared.csv
## Prepare the dataset
prepare: $(DATA)/interim/datas-prepared.csv

$(DATA)/processed/datas-features.csv : $(REQUIREMENTS) air_quality_nairobi/build_features.py $(DATA)/interim/datas-prepared.csv
	@python -O -m air_quality_nairobi.build_features \
		$(DATA)/interim/datas-prepared.csv \
		$(DATA)/processed/datas-features.csv
## Add features
features: $(DATA)/processed/datas-features.csv

models/model.pkl : $(REQUIREMENTS) air_quality_nairobi/train_model.py $(DATA)/processed/datas-features.csv
	@python -O -m air_quality_nairobi.train_model \
		$(SEED) \
		$(BATCH_SIZE) \
		$(EPOCHS) \
		$(DATA)/processed/datas-features.csv \
		models/model.pkl
## Train the model
train: models/model.pkl

reports/metric.json: $(REQUIREMENTS) air_quality_nairobi/evaluate_model.py models/model.pkl
	@python -O -m air_quality_nairobi.evaluate_model \
		models/model.pkl \
		$(DATA)/processed/datas-features.csv \
		reports/metric.json
## Evalutate the model
evaluate: reports/metric.json

## Visualize the result
visualize: $(REQUIREMENTS) air_quality_nairobi/visualize.py models/model.pkl
	@python -O -m air_quality_nairobi.visualize \
	    'reports/*.metric'
