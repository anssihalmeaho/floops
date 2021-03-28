# floops
operation execution library

**floops** is [FunL](https://github.com/anssihalmeaho/funl) module for implementing operations
(name comes from "flow of operations").

Operations:

- are executed in ordered sequence
- can be composed
- can pass data in pipeline (like unix pipes)
- can be executed concurrently and synchronized (like fork-join)
- can rollback/undo

Operations are named procedures. List of operations are executed in sequential order.

If any operation fails rollback is done for all operations which were already executed.

Each operation may have compensating procedure defined which is called in rollback
(if there is not rollback procedure then rollback is not done for that operation).

Some data value (state) can be passed from operation to another in sequence.

When starting sequence execution inital value is given as argument and
after sequence is executed return value contains value which is passed as
output of sequence.

Operation implementation receives as arguments:

1. state (value passed from previous operation)
2. arguments given to operation

It returns **list** containing:

1. is success (**true** if success, **false** if failed)
2. error text (string), can be empty if no failure
3. value (state) passed to next operation (or as result from sequence execution)

If operation has compensating procedure it is called with latest state value
and with same arguments as actual procedure (in rollback).

There is special operation **'join'** which can be used for forking several
concurrent operation sequence executions.

## Related patterns

There are some design patterns which are related to operation concept:

- Saga pattern (compensating transactions)
- Command pattern
- Fork-join model ('join' -operation)
- Pipelines (unix-like)

## Possible usage

Some possible usages for operations are:

- Transactional sequences in microservices
- Automation (Infrastructure-As-Code, Acceptance Testing, Continuous Integration, SW building)
- Automating routine tasks, workflow management
- Parallel data processing (with 'join', similar to Map-Reduce model)
- Any multi-stage task execution with need for rollback

## Services

### run-ops
Runs list of operations.

Arguments are:

1. Map of operation implementations
2. Initial state
3. List of operations to be executed

Map of operation implementations consists of:

- key: operation name (string)
- value: procedure or pair (list of two items) of procedure and compensating procedure

Operation procedure is following kind:

```
proc(<previous-state:value> <arg-1> <arg-2> ...) -> list(<ok:bool> <err-text:string> <state:value>)
```

Compensating procedure is similar kind.

```
call(floops.run-ops <op-impl:map> <init-state:value> <operations:list>) -> list(<ok:bool> <err-text:string> <state:value>)
```

Returns list containing:

1. is success (**true** if success, **false** if failed)
2. error text (string), can be empty if no failure
3. value (state) passed to next operation (or as result from sequence execution)

#### 'join' operation
There is special (builtin) **'join'** -operation which assumes its argument being list
of operations lists.

Each operation list is executed concurrently and all of those synchronized so that
'join' operation waits that all sublists are exectuions are completed.
Resulting state is list of result states of sublists.

'join' operator implements Fork-join type of model.

If any sublist execution fails then all successfully executed operations under 'join' are
cancelled (rollback).

There's builtin compensating procedure for 'join' which cancels all sublists under it
in rollback.

## Get started
Prerequisite is to have [FunL interpreter](https://github.com/anssihalmeaho/funl) compiled.
Clone floops from Github:

```
git clone https://github.com/anssihalmeaho/floops.git
```

Put **floops.fnl** to some directory which can be found under **FUNLPATH** or in working directory.

See more information: https://github.com/anssihalmeaho/funl/wiki/Importing-modules


## Examples

### Example: Basic sequence of operations
Note. this example may work only in unix/linux systems.

```
ns main

main = proc()
	import floops
	import stdos
	import stdbytes

	ops-by-name = map(
		'files'
				proc()
					ok err out errout = call(stdos.exec 'ls'):
					outstr = if(ok call(stdbytes.string out) call(stdbytes.string errout))
					list(ok err outstr)
				end

		'makelist'
				proc(input)
					import stdfu
					list(true '' call(stdfu.filter split(input '\n') func(x) not(eq(x '')) end))
				end
	)

	operations = list(
		list('files')
		list('makelist')
	)

	call(floops.run-ops ops-by-name 'no-state' operations)
end

endns
```

Run __example1.fnl__:

```
./funla examples/example1.fnl
```

Output:

```
list(true, '', list('examples', 'floops.fnl', 'LICENSE', 'README.md'))
```

### Example: Failure and rollback

```
ns main

import floops

get-my-op-implementations = proc()
	map(
		'op-A' list(
			proc()
				state = head(argslist())
				next-state = sprintf('%s -> op-A' state)
				_ = print('op-A: ' argslist())
				list(true '' next-state)
			end
			# this is compensating procedure (called in rollback)
			proc()
				state = head(argslist())
				_ = print('op-A Cancel: ' argslist())
				list(true '' state)
			end
		)

		'op-B'	list(
				proc()
					state = head(argslist())
					next-state = sprintf('%s -> op-B' state)
					_ = print('op-B: ' argslist())
					list(true '' next-state)
				end
				# this is compensating procedure (called in rollback)
				proc()
					state = head(argslist())
					_ = print('op-B Cancel: ' argslist())
					list(true '' state)
				end)

		'op-C' 	proc()
					state = head(argslist())
					_ = print('op-C Fails')
					list(false '' state) # This will cause sequence to fail
				end
	)
end

main = proc()
	op-implementations = call(get-my-op-implementations)

	operations = list(
		list('op-A' split('some arguments'):)
		list('op-B' 100 200)
		list('op-B' map('some key' 'some value'))
		list('op-C') # this will fail
		list('op-A' split('this is never reached')) # this is never reached
	)

	call(floops.run-ops op-implementations 'begin' operations)
end

endns
```

Run __example2.fnl__:

```
./funla examples/example2.fnl
```

Output:

```
op-A: list('begin', 'some', 'arguments')
op-B: list('begin -> op-A', 100, 200)
op-B: list('begin -> op-A -> op-B', map('some key' : 'some value'))
op-C Fails
op-B Cancel: list('begin -> op-A -> op-B -> op-B', map('some key' : 'some value'))
op-B Cancel: list('begin -> op-A -> op-B -> op-B', 100, 200)
op-A Cancel: list('begin -> op-A -> op-B -> op-B', 'some', 'arguments')
list(false, '', 'begin -> op-A -> op-B -> op-B')
```

### Example: Concurrent execution with 'join'

```
ns main

main = proc()
	import floops
	import stdio

	ops-impl = map(
		'op-A' list(
			proc()
				state = head(argslist())
				arg = rest(argslist()):
				_ = call(stdio.printf 'op-A executed (state: %v, arg: %v)\n' state arg)
				list(true '' state)
			end
			proc()
				state = head(argslist())
				arg = rest(argslist()):
				_ = call(stdio.printf 'op-A cancel (state: %v, arg: %v)\n' state arg)
				list(true '' state)
			end
		)

		'op-B'	proc()
					state = head(argslist())
					arg = rest(argslist()):
					_ = call(stdio.printf 'op-B executed (state: %v, arg: %v)\n' state arg)
					list(true '' state)
				end

		'op-Fail'
				proc()
					state = head(argslist())
					arg = rest(argslist()):
					_ = call(stdio.printf 'op-Fail (state: %v, arg: %v)\n' state arg)
					list(false 'some failure' state)
				end

		'subop-1' list(
			proc()
				state = head(argslist())
				number = head(rest(argslist()))
				_ = call(stdio.printf 'subop-1 executed (state: %v, arg: %v)\n' state number)
				list(true '' plus(state number))
			end
			proc()
				state = head(argslist())
				number = head(rest(argslist()))
				_ = call(stdio.printf 'subop-1 cancel (state: %v, arg: %v)\n' state number)
				list(true '' state)
			end
		)

		'subop-2' list(
			proc()
				state = head(argslist())
				number = head(rest(argslist()))
				_ = call(stdio.printf 'subop-2 executed (state: %v, arg: %v)\n' state number)
				list(true '' plus(state number))
			end
			proc()
				state = head(argslist())
				number = head(rest(argslist()))
				_ = call(stdio.printf 'subop-2 cancel (state: %v, arg: %v)\n' state number)
				list(true '' state)
			end
		)
	)

	operations = list(
		list('op-A' 'something')

		# here starts concurrent operation lists execution
		# which are then joined
		list('join'
			list(
				list('subop-1' 1)
				list('subop-2' 2)
			)
			list(
				list('subop-1' 3)
				list('subop-2' 4)
			)

			list(
				# another nested concurrent operation lists exec
				list('join'
					list(
						list('subop-1' 5)
						list('subop-2' 6)
					)
				)
			)
		)
		list('op-B' 'done')
	)

	call(floops.run-ops ops-impl 0 operations)
end

endns
```

Run __example3.fnl__:

```
./funla examples/example3.fnl
```

Output:

```
op-A executed (state: 0, arg: something)
subop-1 executed (state: 0, arg: 5)
subop-2 executed (state: 5, arg: 6)
subop-1 executed (state: 0, arg: 1)
subop-1 executed (state: 0, arg: 3)
subop-2 executed (state: 1, arg: 2)
subop-2 executed (state: 3, arg: 4)
op-B executed (state: list(3, list(11), 7), arg: done)
list(true, '', list(3, list(11), 7))
```

### Example: Failure and rollback with 'join'

```
ns main

main = proc()
	import floops
	import stdio

	ops-impl = map(
		'op-A' list(
			proc()
				state = head(argslist())
				arg = rest(argslist()):
				_ = call(stdio.printf 'op-A executed (state: %v, arg: %v)\n' state arg)
				list(true '' state)
			end
			proc()
				state = head(argslist())
				arg = rest(argslist()):
				_ = call(stdio.printf 'op-A cancel (state: %v, arg: %v)\n' state arg)
				list(true '' state)
			end
		)

		'op-B'	proc()
					state = head(argslist())
					arg = rest(argslist()):
					_ = call(stdio.printf 'op-B executed (state: %v, arg: %v)\n' state arg)
					list(true '' state)
				end

		'op-Fail'
				proc()
					state = head(argslist())
					_ = call(stdio.printf 'op-Fail (state: %v)\n' state)
					list(false 'some failure' state)
				end

		'subop-1' list(
			proc()
				state = head(argslist())
				number = head(rest(argslist()))
				_ = call(stdio.printf 'subop-1 executed (state: %v, arg: %v)\n' state number)
				list(true '' plus(state number))
			end
			proc()
				state = head(argslist())
				number = head(rest(argslist()))
				_ = call(stdio.printf 'subop-1 cancel (state: %v, arg: %v)\n' state number)
				list(true '' state)
			end
		)

		'subop-2' list(
			proc()
				state = head(argslist())
				number = head(rest(argslist()))
				_ = call(stdio.printf 'subop-2 executed (state: %v, arg: %v)\n' state number)
				list(true '' plus(state number))
			end
			proc()
				state = head(argslist())
				number = head(rest(argslist()))
				_ = call(stdio.printf 'subop-2 cancel (state: %v, arg: %v)\n' state number)
				list(true '' state)
			end
		)
	)

	operations = list(
		list('op-A' 'something')

		# here starts concurrent operation lists execution
		# which are then joined
		list('join'
			list(
				list('subop-1' 1)
				list('subop-2' 2)
			)
			list(
				list('subop-1' 3)
				list('subop-2' 4)
				list('op-Fail')
			)

			list(
				# another nested concurrent operation lists exec
				list('join'
					list(
						list('subop-1' 5)
						list('subop-2' 6)
					)
				)
			)
		)
		list('op-B' 'done')
	)

	call(floops.run-ops ops-impl 0 operations)
end

endns
```

Run __example4.fnl__:

```
./funla examples/example4.fnl
```

Output:

```
op-A executed (state: 0, arg: something)
subop-1 executed (state: 0, arg: 5)
subop-1 executed (state: 0, arg: 1)
subop-2 executed (state: 5, arg: 6)
subop-1 executed (state: 0, arg: 3)
subop-2 executed (state: 1, arg: 2)
subop-2 executed (state: 3, arg: 4)
op-Fail (state: 7)
subop-2 cancel (state: 7, arg: 4)
subop-1 cancel (state: 7, arg: 3)
subop-2 cancel (state: 0, arg: 2)
subop-1 cancel (state: 0, arg: 1)
subop-2 cancel (state: 0, arg: 6)
subop-1 cancel (state: 0, arg: 5)
op-A cancel (state: list(list(11), 3), arg: something)
list(false, 'some failure', list(list(11), 3))
```

## To be done

There could be several builtin operations for managing control flow:

For example:

- 'generate': based on in-state generates op-list as output which is executed
- 'if': logical branching
- 'join' variants: no cancel, no synchronization

