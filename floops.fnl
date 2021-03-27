
ns floops

run-ops = proc(ops-map initial-state oper-list)
	import stddbc
	import stdfu

	join-exe = proc()
		state = head(argslist())
		ch = chan()

		run-concur = proc(suboplist idx)
			retv = call(real-run-ops state suboplist)
			replych = chan()
			_ = send(ch list(retv replych idx))
			compl-str ostate = recv(replych):
			this-op-was-ok = head(retv)
			_ = if( this-op-was-ok
				case( compl-str
					'ok'     'nothing to do'
					'cancel' call(run-cancel-ops ostate reverse(suboplist))
				)
				'no need to cancel twice'
			)
			send(ch 'done')
		end

		start-conc-op = proc(suboplist wcount)
			_ = spawn(call(run-concur suboplist wcount))
			plus(wcount 1)
		end

		wait-all-answers = proc(wcount)
			loopy = proc(inlst)
				resl ack-map rlist = inlst:
				while( gt(wcount len(ack-map))
					call(proc()
						lst replych idx = recv(ch):
						ok err val = lst:
						overall-ok = head(resl)
						if( ok
							list(
								if( overall-ok
									list(true '' append(resl val))
									resl
								)
								put(ack-map idx list(true replych))
								append(rlist val)
							)
							list(
								list(false err state)
								put(ack-map idx list(false replych))
								rlist
							)
						)
					end)
					list(resl ack-map rlist)
				)
			end

			all-result = call(loopy list(list(true '' list()) map() list() ))
			all-result
		end

		complete-all = proc(ack-map ostate)
			kvlist = keyvals(ack-map)
			all-ok = call(stdfu.foreach kvlist func(item cum) isok _ = last(item): and(isok cum) end true)
			compl-str = if(all-ok 'ok' 'cancel')

			sender = proc(pair dont-care)
				idx = head(pair)
				_ replych = last(pair):
				_ = send(replych list(compl-str ostate))
				'none'
			end

			wait-all-done = proc(done-cnt)
				while( gt(len(kvlist) done-cnt)
					call(proc()
						_ = recv(ch)
						plus(done-cnt 1)
					end)
					'none'
				)
			end

			_ = call(stdfu.ploop sender kvlist '')
			call(wait-all-done 0)
		end

		oplist = rest(argslist())
		wait-count = call(stdfu.ploop start-conc-op oplist 0)
		result acks rlist = call(wait-all-answers wait-count):
		_ = call(complete-all acks last(result))
		list(head(result) head(rest(result)) rlist)
	end

	join-cancel = proc()
		state = head(argslist())
		ch = chan()

		run-cancel = proc(suboplist idx)
			_ = call(run-cancel-ops state reverse(suboplist))
			send(ch sprintf('done: %d' idx))
		end

		start-cancel-op = proc(suboplist wcount)
			_ = spawn(call(run-cancel suboplist wcount))
			plus(wcount 1)
		end

		wait-all-cancels-done = proc(done-cnt cnt)
			while( gt(done-cnt cnt)
				done-cnt
				call(proc()
					_ = recv(ch)
					plus(cnt 1)
				end)
				'none'
			)
		end

		oplist = rest(argslist())
		wait-count = call(stdfu.ploop start-cancel-op oplist 0)
		_ = call(wait-all-cancels-done wait-count 0)

		list(true '' head(argslist())) # return value doesnt matter
	end

	trans-ops = proc(ops oplist)
		converter = proc(opitem)
			opname = head(opitem)
			opargs = rest(opitem)

			found op-impl = getl(ops opname):
			_ = call(stddbc.assert found sprintf('operation %s not found' opname))
			case( opname
				'join' list(list(opname join-exe join-cancel) call(stdfu.proc-apply opargs proc(x) call(stdfu.proc-apply x converter) end):)

				case( type(op-impl)
					'list'     list(list(opname head(op-impl) last(op-impl)) opargs:)
					'function' list(list(opname op-impl proc() list(true '' last(argslist())) end) opargs:)
				)
			)
		end

		call(stdfu.proc-apply oplist converter)
	end

	run-cancel-ops = proc(init-state oplist)
		do-nextop = proc(op-item rest-ops prev-state)
			op-impl = head(op-item)
			opname = head(op-impl)
			_ cancel-proc = rest(op-impl):
			opargs = rest(op-item)

			_ = try(call(cancel-proc prev-state opargs:))

			if( empty(rest-ops)
				list(true '' prev-state)
				call(proc()
					_ = call(do-nextop head(rest-ops) rest(rest-ops) prev-state):
					list(true '' prev-state)
				end)
			)
		end

		call(do-nextop head(oplist) rest(oplist) init-state)
	end

	real-run-ops = proc(init-state oplist)
		import stddbc

		do-nextop = proc(op-item rest-ops prev-state)
			op-impl = head(op-item)
			opname = head(op-impl)
			op-proc cancel-proc = rest(op-impl):
			opargs = rest(op-item)

			op-retval = try(call(op-proc prev-state opargs:))
			result-ok result-err next-state = case( type(op-retval)
				'list'   op-retval
				'string' list(false sprintf('operation %s made RTE (%s)' opname op-retval) prev-state)
			):

			if( result-ok
				if( empty(rest-ops)
					list(result-ok result-err next-state)
					call(proc()
						op-ok op-err nstate = call(do-nextop head(rest-ops) rest(rest-ops) next-state):
						_ = if( not(op-ok)
							try(call(cancel-proc nstate opargs:))
							'none'
						)
						list(op-ok op-err nstate)
					end)
				)
				list(false result-err next-state)
			)
		end

		call(do-nextop head(oplist) rest(oplist) init-state)
	end

	new-ops-map = put(ops-map 'join' list(join-exe join-cancel))
	new-operlist = call(trans-ops new-ops-map oper-list)
	call(real-run-ops initial-state new-operlist)
end

endns

