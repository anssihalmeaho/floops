
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

