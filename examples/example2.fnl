
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

