.PHONY: clean

default: Dockerfile get-inner-img.sh
	./get-inner-img.sh
	docker build -t nestybox/test-syscont .

clean:
	./get-inner-img.sh -c
