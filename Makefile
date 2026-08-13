.PHONY: build test open

build:
	zsh scripts/build.sh

test:
	mkdir -p .build
	swiftc -parse-as-library \
		-target arm64-apple-macosx14.0 \
		-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
		-o .build/logic-tests \
		Sources/PunchReminder/Models.swift \
		Sources/PunchReminder/ReminderLogic.swift \
		scripts/LogicTests.swift
	.build/logic-tests

open: build
	open ".build/朝夕打卡.app"

install: build
	rm -rf "/Applications/朝夕打卡.app" "/Applications/朝夕闹钟.app"
	cp -R ".build/朝夕打卡.app" "/Applications/朝夕打卡.app"
	open "/Applications/朝夕打卡.app"
