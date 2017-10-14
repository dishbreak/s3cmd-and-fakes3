# Fake S3 Proof Of Concept

## Introduction

This experiment proves that:

* It is possible to launch a fake-s3 container from its [publicly available Docker Hub image](https://hub.docker.com/r/lphoward/fake-s3/)
* It is possible to use `s3cmd` with this fake-s3 container.
* Tools like AWS CLI can communicate with this fake-s3 container.

## Usage

Launch the Docker compose network.

    $ docker-compose up -d
    Starting s3cmdandfakes3_fakes3_1 ...
    Starting s3cmdandfakes3_fakes3_1 ... done
    $ docker ps --filter name=fakes3 --format "container {{.ID}} is {{.Names}} on {{.Ports}}"
    container a86dee26bf48 is s3cmdandfakes3_fakes3_1 on 0.0.0.0:4569->4569/tcp

This launches the fake-s3 container. It's available on our docker-machine, on port 4569. It also sets up additional DNS aliases which s3cmd needs. But more on that later.

You can copy arbitrary files to the fake S3 using the AWS CLI. Note the `endpoint` flag.

   $ echo "hi this is a test" > foo.txt
   $ aws s3 --endpoint cp http://192.168.99.100:4569 foo.txt s3://my-bucket/
   upload: ./foo.txt to s3://my-bucket/foo.txt

Now, launch the Docker container with the s3cmd binary installed. There's a script in `s3cmd/` that will do that for you. The script does the following things.

* Downloads the `garland/docker-s3cmd` binary.
* Creates a custom container based off of it that has a special config file.
* Launches an instance of the custom container and attaches a shell session to it.

    $ ./connect_to_fake_s3.sh
    Sending build context to Docker daemon  4.608kB
    Step 1/2 : FROM garland/docker-s3cmd
    latest: Pulling from garland/docker-s3cmd
    957bc456a443: Pull complete
    67936e52ee40: Pull complete
    55452a1b5b06: Pull complete
    2cc40fd14a64: Pull complete
    e2bca7bdbcb7: Pull complete
    832118e2d256: Pull complete
    fba2a6b9e7dd: Pull complete
    0717a11f3123: Pull complete
    ab7b09567bf9: Pull complete
    6a405c959218: Pull complete
    8e2dbe3d230c: Pull complete
    Digest: sha256:37e97dcd546429060d76704b03e2b0cc9cd99073cfc1c7ddb63a4e8080a2736c
    Status: Downloaded newer image for garland/docker-s3cmd:latest
     ---> 9f1da0e43017
    Step 2/2 : COPY s3cfg.txt /root/.s3cfg
     ---> 7deb2114b4b5
    Successfully built 7deb2114b4b5
    Successfully tagged fakeds3cmd:latest
    / #

We can use this container and download the file we put in fake s3.

    / # s3cmd get s3://my-bucket/foo.txt
    download: 's3://my-bucket/foo.txt' -> './foo.txt'  [1 of 1]
     18 of 18   100% in    0s  1750.80 B/s  done
    / # cat foo.txt
    hi this is a test

That's about it.

## Network Aliases

s3cmd expects to access S3 buckets by subdomain. 

    host_base = fakes3:4569
    host_bucket = %(bucket)s.fakes3:4569

That means that we need to configure it to resolve `<bucket-name>.fakes3` back to the fake-s3 container. Docker Compose makes this really easy to do with network aliases. See the following snippet.

        networks:
          # This is the network that our s3cmd container will join when it launches.
          s3cmd-network:
            aliases:
              # This allows us to use `my-bucket` as a name in s3cmd
              - my-bucket.fakes3

And looking at our `./connect_to_fake_s3.sh` script, we can see that our `fakeds3` container also joins this network.

    docker run -it --network='s3cmdandfakes3_s3cmd-network' fakeds3cmd /bin/sh

Indeed, if you run the script, you'll be able to resolve both `fakes3` and `my-bucket.fakes3`

    $ ./connect_to_fake_s3.sh
    ...
    / # ping fakes3
    PING fakes3 (172.18.0.2): 56 data bytes
    64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.071 ms
    64 bytes from 172.18.0.2: seq=1 ttl=64 time=0.107 ms
    64 bytes from 172.18.0.2: seq=2 ttl=64 time=0.106 ms
    ^C
    --- fakes3 ping statistics ---
    3 packets transmitted, 3 packets received, 0% packet loss
    round-trip min/avg/max = 0.071/0.094/0.107 ms
    / # ping my-bucket.fakes3
    PING my-bucket.fakes3 (172.18.0.2): 56 data bytes
    64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.057 ms
    64 bytes from 172.18.0.2: seq=1 ttl=64 time=0.106 ms
    64 bytes from 172.18.0.2: seq=2 ttl=64 time=0.102 ms
    64 bytes from 172.18.0.2: seq=3 ttl=64 time=0.087 ms
    ^C
    --- my-bucket.fakes3 ping statistics ---
    4 packets transmitted, 4 packets received, 0% packet loss
    round-trip min/avg/max = 0.057/0.088/0.106 ms

