require 'bundler/setup'
require 'matrix'

module Kamelopard
    module Multicam
        def self.cross_product(v1, v2)
            x =   ( (v1[1] * v2[2]) - (v1[2] * v2[1]) )
            y = - ( (v1[0] * v2[2]) - (v1[2] * v2[0]) )
            z =   ( (v1[0] * v2[1]) - (v1[1] * v2[0]) )
            return Vector[x, y, z]
        end

        def self.dotprod_angle(a, b, negate = false)
            begin
                d = 180.0 * (Math.acos(a.inner_product(b) / a.r / b.r)) / Math::PI
            rescue
                d = 0
                #puts "argument was #{a.inner_product(b)}, from vectors #{a} and #{b}"
            end
            d = 0 if d.respond_to? :nan? and d.nan?
            raise "#{a}, #{b}, #{a.inner_product(b)}" if d == Float::INFINITY

            # Complicating factor: dot product goes from 0 to 180, not 0 to 360. We'll
            # have to know whether to negate based on external input (like if the
            # original angle involved was close to the threshold)
            d = -d if negate

            return d
        end

        def self.rot_x(a)
            # This, and the other two rotation matrix functions, must convert
            # the angle to radians
            a = a * Math::PI / 180.0
            return Matrix[[1, 0, 0], [0, Math.cos(a), -1 * Math.sin(a)], [0, Math.sin(a), Math.cos(a)]]
        end

        def self.rot_y(a)
            a = a * Math::PI / 180.0
            return Matrix[[Math.cos(a), 0, Math.sin(a)], [0, 1, 0], [-1 * Math.sin(a), 0, Math.cos(a)]]
        end

        def self.rot_z(a)
            a = a * Math::PI / 180.0
            return Matrix[[Math.cos(a), -1 * Math.sin(a), 0], [Math.sin(a), Math.cos(a), 0], [0, 0, 1]]
        end

        def self.same_quadrant(a, b)
            (0..2).each do |i|
                return false if (a[i] > 0 and b[i] < 0) or (a[i] < 0 and b[i] > 0)
            end
            return true
        end

        # Vec is the camera vector. up_vec is the vector out the top of the camera
        def self.vector_to_camera(vec, up_vec)
            # The heading is the angle between two planes, the first formed by the
            # camera vector and the original Z axis, and the second formed by the
            # original Y and Z axes. This angle between two planes is the same
            # as the angle between their two normals. The normal of the first
            # plane is the cross product of the two vector, and that of the
            # second is simply the X axis. The first cross product will be zero
            # if the camera position vector is parallel to the Z axis; in that
            # case we want the angle between the up vector and the y axis
            # This will only find values up to 180 degrees, and won't
            # distinguish direction correctly. For that, look at the Z
            # component of the cross product of the two normals.
            cam_z_norm = cross_product(vec, Vector[0,0,-1])
            if cam_z_norm.r == 0
                heading = dotprod_angle(up_vec, Vector[0,1,0],
                    (cross_product(up_vec, Vector[0,1,0])[2] > 0))
            else
                heading = dotprod_angle(cam_z_norm, Vector[1,0,0],
                    (cross_product(cam_z_norm, Vector[1,0,0])[2] > 0))
            end

            # Tilt is calculated from the vector alone, and is the angle between it and
            # the original Z axis, calculated via the dot product
            tilt = dotprod_angle(vec, Vector[0,0,1])

            # For roll, take the original UP vector, and now that I've got
            # valid heading and tilt, transform it by those values. Take the
            # angle between it and my current UP vector. Make it negative if
            # their cross product, up vector first, isn't the same direction as
            # the camera vector.
            transformed_up = rot_z(heading) * rot_x(tilt) * Vector[0,1,0]
            if cross_product(up_vec, transformed_up).r == 0
                negate = ! (same_quadrant(up_vec, transformed_up))
            else
                negate = same_quadrant(vec, cross_product(up_vec, transformed_up))
            end
            roll = dotprod_angle(up_vec, transformed_up, negate)

            return [heading, tilt, roll]
        end

        def self.make_placemark(name, lat, lon, alt, tilt, roll, heading)
            p = point(lon, lat, alt, :relativeToGround)
            l = camera p, :heading => heading, :tilt => tilt, :roll => roll, :altitudeMode => :relativeToGround
            pl = placemark(name, :geometry => p, :abstractView => l)
            f = get_folder
            f << pl
        end

        def self.get_camera(heading, tilt, roll, cam_num, cam_angle, cam_count = nil)
            if cam_angle.nil? then
                cam_angle = cam_num * 360.0 / cam_count
            else
                cam_angle = cam_angle * cam_num
            end
            # The camera vector is [0,0,1] rotated around the Y axis the amount
            # of the camera angle
            camera = rot_y(cam_angle) * Vector[0,0,1]

            # The up vector is the same for all cameras
            up = Vector[0,1,0]
            matrix = rot_z(heading) * rot_x(tilt) * rot_z(roll)
            (h, t, r) = vector_to_camera(matrix * camera, matrix * up)
            # XXX What am I getting wrong, to require the negated roll?
            return [h, t, -1 * r]
        end

        def self.get_camera_view(v, cam_num, cam_angle, cam_count = nil)
            (h, t, r) = get_camera(v.heading, v.tilt, v.roll, cam_num, cam_angle, cam_count)
            v.heading = h
            v.tilt = t
            v.roll = r
            v
        end

        def self.test(kml_name = 'multicam_test.kml')
            name_document 'tourvid'
            get_document().open = 1

            [:roll, :tilt, :heading].each do |which|
                camera = Vector[0,0,1]
                heading = 0
                tilt = 45
                roll = 0
                lat = 40
                lon = -111
                alt = 100

                puts "------------------"
                puts "Running #{which}"
                folder which.to_s
                get_folder().open = 1

                up = Vector[0,1,0]
                (0..36).each do |i|
                    if which == :roll then
                        roll = -180 + i * 10
                        heading = 23
                    elsif which == :heading then
                        heading = i * 10
                        heading = heading - 360 if heading >= 180
                    else
                        tilt = i * 5
                    end

                    # This has been verified visually as the right matrix
                    matrix = rot_z(heading) * rot_x(tilt) * rot_z(roll)

                    trans_up = matrix * up
                    trans_cam = matrix * camera
                    trans_cross = cross_product(trans_cam, trans_up)
                    (screen_head, screen_tilt, screen_roll) = vector_to_camera(trans_cam, trans_up)

                    diff_limit = 3
                    a = dotprod_angle(trans_up, trans_cam)
                    if ((heading - screen_head).abs > diff_limit or (tilt - screen_tilt).abs > diff_limit or (roll - screen_roll).abs > diff_limit) then
                    #if which == :roll then
                        puts "  PLACEMARK #{i}"
#                        puts "    Camera vector: #{trans_cam}, mag: #{trans_cam.r}"
#                        puts "    Up vector: #{trans_up}, mag: #{trans_up.r}"
#                        puts "    Cross prod: #{trans_cross}, mag: #{trans_cross.r}"
                        puts "    UpZ: #{trans_up[2]}"
                        puts "    Orig H/T/R: #{heading}/#{tilt}/#{roll}"
                        puts "    Screen H/T/R: #{screen_head}/#{screen_tilt}/#{screen_roll}"
                    end
                    make_placemark(i, lat, lon, alt, screen_tilt, screen_roll, screen_head)
                end
                puts
                write_kml_to kml_name
            end
        end
    end
end
