#!/usr/bin/env bats

#
# Basic tests running docker inside a system container
#

load ../helpers/run
load ../helpers/docker
load ../helpers/net
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function basic_test {
   net=$1

   # Launch swarm manager sys container
   local mgr=$(docker_run --rm --name manager --net=$net nestybox/alpine-docker-dbg:latest tail -f /dev/null)

   # init swarm in manager, get join token
   docker exec -d $mgr sh -c "dockerd > /var/log/dockerd.log 2>&1"
   [ "$status" -eq 0 ]

   wait_for_inner_dockerd $mgr

   docker exec $mgr sh -c "docker swarm init"
   [ "$status" -eq 0 ]

   docker exec $mgr sh -c "docker swarm join-token -q manager"
   [ "$status" -eq 0 ]
   local mgr_token="$output"

   docker exec $mgr sh -c "ip a"
   [ "$status" -eq 0 ]
   local mgr_ip=$(parse_ip "$output" "eth0")

   local join_cmd="docker swarm join --token $mgr_token $mgr_ip:2377"

   # Launch worker node
   local worker=$(docker_run --rm --name worker --net=$net nestybox/alpine-docker-dbg:latest tail -f /dev/null)

   # Join the worker to the swarm
   docker exec -d $worker sh -c "dockerd > /var/log/dockerd.log 2>&1"
   [ "$status" -eq 0 ]

   wait_for_inner_dockerd $worker

   docker exec $worker sh -c "$join_cmd"
   [ "$status" -eq 0 ]

   # verify worker node joined
   docker exec $mgr sh -c "docker node ls"
   [ "$status" -eq 0 ]

   # The output of the prior command is something like this:
   #
   # ID                            HOSTNAME            STATUS              AVAILABILITY        MANAGER STATUS      ENGINE VERSION
   # by9ukwes9r9emn3pbozbh6dp6     7f62c95195dc        Ready               Active              Reachable           19.03.12
   # sfgwme7k5vol5ra3hf2jgwlfo *   fc4c806f1598        Ready               Active              Leader              19.03.12

   for i in $(seq 1 2); do
      [[ "${lines[$i]}" =~ "Ready".+"Active" ]]
   done

   # deploy a service
   docker exec $mgr sh -c "docker service create --replicas 4 --name helloworld alpine ping docker.com"
   [ "$status" -eq 0 ]

   # verify the service is up
   docker exec $mgr sh -c "docker service ls"
   [ "$status" -eq 0 ]
   [[ "${lines[1]}" =~ "$helloworld".+"4/4" ]]

   # cleanup
   docker_stop $mgr
   docker_stop $worker
}

@test "swarm-in-docker basic" {
   basic_test bridge
 }

@test "swarm-in-docker custom net" {

   docker network create test-net
   [ "$status" -eq 0 ]

   basic_test test-net

   docker network rm test-net
   [ "$status" -eq 0 ]
}
